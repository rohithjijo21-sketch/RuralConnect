import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { pool, transaction } from './db.js';
import { hash, safeFare, type Actor } from './domain.js';
import type { PoolClient } from 'pg';
@Injectable()
export class Bookings {
  async eligible(db: PoolClient, actor: Actor, vehicleId: string) {
    if (!actor.roles.includes('DRIVER')) throw new ForbiddenException();
    const v = (
      await db.query(
        "SELECT v.* FROM vehicles v JOIN driver_profiles d ON d.user_id=v.driver_id JOIN users u ON u.id=d.user_id WHERE v.id=$1 AND v.driver_id=$2 AND v.approved AND d.verification='APPROVED' AND NOT u.suspended",
        [vehicleId, actor.id],
      )
    ).rows[0];
    if (!v) throw new ForbiddenException('An approved driver and vehicle are required');
    return v;
  }
  async idempotent(
    db: PoolClient,
    actor: Actor,
    key: string,
    input: unknown,
    work: () => Promise<any>,
  ) {
    const digest = hash(JSON.stringify(input));
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [actor.id + ':' + key]);
    const old = (
      await db.query('SELECT * FROM idempotency_keys WHERE actor_id=$1 AND key=$2', [actor.id, key])
    ).rows[0];
    if (old) {
      if (old.request_hash !== digest)
        throw new ConflictException('Idempotency key reused with different input');
      return old.response;
    }
    const response = await work();
    await db.query(
      'INSERT INTO idempotency_keys(actor_id,key,request_hash,response) VALUES($1,$2,$3,$4)',
      [actor.id, key, digest, JSON.stringify(response)],
    );
    return response;
  }
  async sharedCreate(
    actor: Actor,
    input: {
      vehicleId: string;
      departureAt: string;
      capacity: number;
      farePaise: number;
      stops: { name: string; lat: number; lng: number }[];
    },
  ) {
    return transaction(async (db) => {
      const v = await this.eligible(db, actor, input.vehicleId);
      if (
        v.category !== 'AUTO' ||
        input.capacity > v.capacity ||
        new Date(input.departureAt) <= new Date()
      )
        throw new ConflictException('Invalid vehicle capacity or departure');
      const t = (
        await db.query(
          "INSERT INTO shared_trips(driver_id,vehicle_id,departure_at,capacity,fare_paise,status) VALUES($1,$2,$3,$4,$5,'PUBLISHED') RETURNING *",
          [actor.id, v.id, input.departureAt, input.capacity, input.farePaise],
        )
      ).rows[0];
      for (const [i, s] of input.stops.entries())
        await db.query(
          'INSERT INTO shared_trip_stops(trip_id,name,point,sequence) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography,$5)',
          [t.id, s.name, s.lng, s.lat, i],
        );
      return t;
    });
  }
  async sharedList() {
    const trips = (
      await pool.query(
        "SELECT t.id,t.departure_at,t.capacity,t.fare_paise,t.status,t.version,(SELECT json_agg(json_build_object('sequence',s.sequence,'name',s.name) ORDER BY s.sequence) FROM shared_trip_stops s WHERE s.trip_id=t.id) stops FROM shared_trips t WHERE status IN ('PUBLISHED','BOARDING') AND bookings_open AND departure_at>now() ORDER BY departure_at LIMIT 100",
      )
    ).rows;
    for (const trip of trips) {
      const counts = (
        await pool.query(
          "SELECT s.sequence,COALESCE(sum(r.seats),0)::int occupied FROM shared_trip_stops s LEFT JOIN seat_reservations r ON r.trip_id=s.trip_id AND r.pickup_sequence<=s.sequence AND r.dropoff_sequence>s.sequence AND r.status IN ('CONFIRMED','BOARDED') WHERE s.trip_id=$1 AND s.sequence<(SELECT max(sequence) FROM shared_trip_stops WHERE trip_id=$1) GROUP BY s.sequence ORDER BY s.sequence",
          [trip.id],
        )
      ).rows;
      trip.availableBySegment = counts.map((c) => ({
        sequence: c.sequence,
        available: trip.capacity - c.occupied,
      }));
      trip.availableSeats = Math.min(...trip.availableBySegment.map((c: any) => c.available));
    }
    return trips;
  }
  async reserve(
    actor: Actor,
    id: string,
    input: { seats: number; pickupSequence: number; dropoffSequence: number },
    key: string,
  ) {
    if (!actor.roles.includes('PASSENGER')) throw new ForbiddenException();
    return transaction((db) =>
      this.idempotent(db, actor, key, { kind: 'reserve', id, ...input }, async () => {
        // Every reservation/cancellation acquires the same trip row lock. Segment occupancy is authoritative.
        const t = (await db.query('SELECT * FROM shared_trips WHERE id=$1 FOR UPDATE', [id]))
          .rows[0];
        if (!t) throw new NotFoundException();
        if (
          !['PUBLISHED', 'BOARDING'].includes(t.status) ||
          !t.bookings_open ||
          t.departure_at <= new Date() ||
          t.driver_id === actor.id
        )
          throw new ConflictException('Bookings closed');
        if (input.pickupSequence >= input.dropoffSequence)
          throw new ConflictException('Invalid stop order');
        const stops = await db.query(
          'SELECT sequence FROM shared_trip_stops WHERE trip_id=$1 AND sequence=ANY($2::int[])',
          [id, [input.pickupSequence, input.dropoffSequence]],
        );
        if (stops.rowCount !== 2) throw new ConflictException('Stops are not on this trip');
        if (
          (
            await db.query(
              "SELECT 1 FROM seat_reservations WHERE trip_id=$1 AND passenger_id=$2 AND status IN ('CONFIRMED','BOARDED')",
              [id, actor.id],
            )
          ).rowCount
        )
          throw new ConflictException('Already reserved');
        const reservations = (
          await db.query(
            "SELECT pickup_sequence,dropoff_sequence,seats FROM seat_reservations WHERE trip_id=$1 AND status IN ('CONFIRMED','BOARDED')",
            [id],
          )
        ).rows;
        for (let segment = input.pickupSequence; segment < input.dropoffSequence; segment++) {
          const occupied = reservations
            .filter((r) => r.pickup_sequence <= segment && r.dropoff_sequence > segment)
            .reduce((sum, r) => sum + r.seats, 0);
          if (occupied + input.seats > t.capacity)
            throw new ConflictException('Insufficient seats');
        }
        const r = (
          await db.query(
            'INSERT INTO seat_reservations(trip_id,passenger_id,pickup_sequence,dropoff_sequence,seats,fare_paise) VALUES($1,$2,$3,$4,$5,$6) RETURNING *',
            [
              id,
              actor.id,
              input.pickupSequence,
              input.dropoffSequence,
              input.seats,
              safeFare(input.seats, t.fare_paise),
            ],
          )
        ).rows[0];
        await db.query('UPDATE shared_trips SET version=version+1 WHERE id=$1', [id]);
        return r;
      }),
    );
  }
  async cancelReservation(actor: Actor, id: string) {
    return transaction(async (db) => {
      const found = (
        await db.query('SELECT trip_id FROM seat_reservations WHERE id=$1 AND passenger_id=$2', [
          id,
          actor.id,
        ])
      ).rows[0];
      if (!found) throw new NotFoundException();
      const t = (
        await db.query('SELECT * FROM shared_trips WHERE id=$1 FOR UPDATE', [found.trip_id])
      ).rows[0];
      if (!['PUBLISHED', 'BOARDING'].includes(t.status) || t.departure_at <= new Date())
        throw new ConflictException('Cancellation window closed');
      const r = (
        await db.query(
          "UPDATE seat_reservations SET status='CANCELLED' WHERE id=$1 AND status='CONFIRMED' RETURNING *",
          [id],
        )
      ).rows[0];
      if (!r) throw new ConflictException('Reservation cannot be cancelled');
      await db.query('UPDATE shared_trips SET version=version+1 WHERE id=$1', [t.id]);
      return r;
    });
  }
  async sharedStatus(actor: Actor, id: string, status: string) {
    return transaction(async (db) => {
      const t = (await db.query('SELECT * FROM shared_trips WHERE id=$1 FOR UPDATE', [id])).rows[0];
      if (!t || t.driver_id !== actor.id) throw new ForbiddenException();
      await this.eligible(db, actor, t.vehicle_id);
      const allowed: Record<string, string[]> = {
        PUBLISHED: ['BOARDING', 'CANCELLED'],
        BOARDING: ['IN_PROGRESS', 'CANCELLED'],
        IN_PROGRESS: ['COMPLETED'],
        COMPLETED: [],
        CANCELLED: [],
      };
      if (!allowed[t.status]?.includes(status))
        throw new ConflictException('Invalid shared trip transition');
      if (status === 'CANCELLED')
        await db.query(
          "UPDATE seat_reservations SET status='CANCELLED' WHERE trip_id=$1 AND status='CONFIRMED'",
          [id],
        );
      if (status === 'COMPLETED')
        await db.query(
          "UPDATE seat_reservations SET status=CASE WHEN status='BOARDED' THEN 'COMPLETED' ELSE 'NO_SHOW' END WHERE trip_id=$1 AND status IN ('CONFIRMED','BOARDED')",
          [id],
        );
      return (
        await db.query(
          'UPDATE shared_trips SET status=$1,bookings_open=$2,version=version+1 WHERE id=$3 RETURNING *',
          [status, status === 'BOARDING', id],
        )
      ).rows[0];
    });
  }

  async driverShared(actor: Actor) {
    if (!actor.roles.includes('DRIVER')) throw new ForbiddenException();
    const trips = (
      await pool.query(
        'SELECT * FROM shared_trips WHERE driver_id=$1 ORDER BY departure_at DESC LIMIT 50',
        [actor.id],
      )
    ).rows;
    for (const t of trips) {
      t.stops = (
        await pool.query(
          'SELECT name,sequence FROM shared_trip_stops WHERE trip_id=$1 ORDER BY sequence',
          [t.id],
        )
      ).rows;
      t.reservations = (
        await pool.query(
          'SELECT r.id,r.pickup_sequence,r.dropoff_sequence,r.seats,r.status,u.name passenger_name FROM seat_reservations r JOIN users u ON u.id=r.passenger_id WHERE r.trip_id=$1 ORDER BY r.created_at',
          [t.id],
        )
      ).rows;
    }
    return trips;
  }
  async boarding(actor: Actor, id: string, status: 'BOARDED' | 'NO_SHOW') {
    return transaction(async (db) => {
      const r = (await db.query('SELECT * FROM seat_reservations WHERE id=$1', [id])).rows[0];
      if (!r) throw new NotFoundException();
      const t = (await db.query('SELECT * FROM shared_trips WHERE id=$1 FOR UPDATE', [r.trip_id]))
        .rows[0];
      if (t.driver_id !== actor.id) throw new ForbiddenException();
      await this.eligible(db, actor, t.vehicle_id);
      if (
        !['BOARDING', 'IN_PROGRESS'].includes(t.status) ||
        (status === 'BOARDED' && t.status !== 'BOARDING') ||
        (status === 'NO_SHOW' && t.departure_at > new Date())
      )
        throw new ConflictException('Boarding/no-show not permitted at this time');
      const updated = (
        await db.query(
          "UPDATE seat_reservations SET status=$1 WHERE id=$2 AND status='CONFIRMED' RETURNING *",
          [status, id],
        )
      ).rows[0];
      if (!updated) throw new ConflictException('Reservation no longer confirmed');
      await db.query(
        'INSERT INTO passenger_boarding_events(reservation_id,actor_id,kind) VALUES($1,$2,$3)',
        [id, actor.id, status],
      );
      await db.query('UPDATE shared_trips SET version=version+1 WHERE id=$1', [t.id]);
      return updated;
    });
  }
  async privateCreate(
    actor: Actor,
    input: {
      pickup: { lat: number; lng: number };
      dropoff: { lat: number; lng: number };
      category: string;
      pickupLabel?: string;
      dropoffLabel?: string;
      expectedFarePaise?: number;
    },
    key: string,
  ) {
    if (!actor.roles.includes('PASSENGER')) throw new ForbiddenException();
    return transaction((db) =>
      this.idempotent(db, actor, key, { kind: 'private', ...input }, async () => {
        await db.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [actor.id]);
        if (
          (
            await db.query(
              "SELECT 1 FROM private_bookings WHERE passenger_id=$1 AND (status IN ('ACCEPTED','ARRIVED','IN_PROGRESS') OR (status='REQUESTED' AND created_at>=now()-interval '3 minutes'))",
              [actor.id],
            )
          ).rowCount
        )
          throw new ConflictException('You already have an active ride');
        // Beta prices are excluded when invitation beta mode is disabled.
        const policy = (
          await db.query(
            'SELECT * FROM fare_policies WHERE category=$1 AND (NOT beta_only OR $2) ORDER BY version DESC LIMIT 1',
            [input.category, process.env.BETA_AUTH_ENABLED === 'true'],
          )
        ).rows[0];
        if (!policy) throw new ConflictException('No approved fare policy configured');
        const distance = (
          await db.query(
            'SELECT ST_Distance(ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography) meters',
            [input.pickup.lng, input.pickup.lat, input.dropoff.lng, input.dropoff.lat],
          )
        ).rows[0].meters;
        if (distance < 50 || distance > 100000)
          throw new ConflictException('Choose locations between 50 metres and 100 km apart');
        // An explicit distance-based estimate, never represented as road-route distance.
        const fare = policy.base_paise + Math.ceil(distance / 1000) * policy.per_km_paise;
        if (input.expectedFarePaise !== undefined && fare !== input.expectedFarePaise)
          throw new ConflictException('Fare changed. Get a new estimate before requesting.');
        const r = (
          await db.query(
            'INSERT INTO ride_requests(passenger_id,pickup,dropoff,category,pickup_label,dropoff_label) VALUES($1,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography,$6,$7,$8) RETURNING id',
            [
              actor.id,
              input.pickup.lng,
              input.pickup.lat,
              input.dropoff.lng,
              input.dropoff.lat,
              input.category,
              input.pickupLabel ?? 'Pickup',
              input.dropoffLabel ?? 'Destination',
            ],
          )
        ).rows[0];
        return (
          await db.query(
            'INSERT INTO private_bookings(request_id,passenger_id,fare_paise) VALUES($1,$2,$3) RETURNING *',
            [r.id, actor.id, fare],
          )
        ).rows[0];
      }),
    );
  }
  async privateAccept(actor: Actor, id: string, vehicleId: string) {
    return transaction(async (db) => {
      const v = await this.eligible(db, actor, vehicleId);
      const d = (
        await db.query('SELECT online FROM driver_profiles WHERE user_id=$1 FOR UPDATE', [actor.id])
      ).rows[0];
      if (!d.online) throw new ForbiddenException('Driver must be online');
      if (
        (
          await db.query(
            "SELECT 1 FROM private_bookings WHERE driver_id=$1 AND status IN ('ACCEPTED','ARRIVED','IN_PROGRESS')",
            [actor.id],
          )
        ).rowCount
      )
        throw new ConflictException('Finish your current ride first');
      const b = (
        await db.query(
          "SELECT b.*,r.category, EXISTS(SELECT 1 FROM driver_locations l WHERE l.user_id=$2 AND l.recorded_at BETWEEN now()-interval '60 seconds' AND now() AND ST_DWithin(l.point,r.pickup,8000)) nearby FROM private_bookings b JOIN ride_requests r ON r.id=b.request_id WHERE b.id=$1 FOR UPDATE OF b",
          [id, actor.id],
        )
      ).rows[0];
      if (!b) throw new NotFoundException();
      if (
        b.passenger_id === actor.id ||
        b.status !== 'REQUESTED' ||
        b.category !== v.category ||
        !b.nearby ||
        new Date(b.created_at).getTime() < Date.now() - 180000 ||
        (
          await db.query(
            'SELECT 1 FROM private_offer_rejections WHERE booking_id=$1 AND driver_id=$2',
            [id, actor.id],
          )
        ).rowCount
      )
        throw new ConflictException('Offer unavailable');
      const updated = (
        await db.query(
          "UPDATE private_bookings SET driver_id=$1,vehicle_id=$2,status='ACCEPTED',version=version+1 WHERE id=$3 RETURNING *",
          [actor.id, vehicleId, id],
        )
      ).rows[0];
      await db.query(
        "INSERT INTO booking_state_history(booking_id,actor_id,from_state,to_state) VALUES($1,$2,'REQUESTED','ACCEPTED')",
        [id, actor.id],
      );
      return updated;
    });
  }
  async privateStatus(actor: Actor, id: string, status: string, version: number) {
    return transaction(async (db) => {
      const b = (await db.query('SELECT * FROM private_bookings WHERE id=$1 FOR UPDATE', [id]))
        .rows[0];
      if (!b) throw new NotFoundException();
      const driver = b.driver_id === actor.id;
      if (!driver && b.passenger_id !== actor.id) throw new ForbiddenException();
      if (driver) await this.eligible(db, actor, b.vehicle_id);
      if (status === 'IN_PROGRESS' && !b.pickup_confirmed_at)
        throw new ConflictException('The passenger must confirm pickup before the trip starts');
      const flow: Record<string, string[]> = {
        REQUESTED: ['CANCELLED'],
        ACCEPTED: ['ARRIVED', 'CANCELLED'],
        ARRIVED: ['IN_PROGRESS', 'CANCELLED'],
        IN_PROGRESS: ['COMPLETED'],
        COMPLETED: [],
        CANCELLED: [],
      };
      if (
        b.version !== version ||
        !flow[b.status]?.includes(status) ||
        (!driver && status !== 'CANCELLED')
      )
        throw new ConflictException('Invalid booking transition');
      await db.query(
        'INSERT INTO booking_state_history(booking_id,actor_id,from_state,to_state) VALUES($1,$2,$3,$4)',
        [id, actor.id, b.status, status],
      );
      return (
        await db.query(
          'UPDATE private_bookings SET status=$1,version=version+1 WHERE id=$2 RETURNING *',
          [status, id],
        )
      ).rows[0];
    });
  }
  async cash(actor: Actor, id: string, key: string) {
    return transaction((db) =>
      this.idempotent(db, actor, key, { kind: 'cash', id }, async () => {
        const b = (await db.query('SELECT * FROM private_bookings WHERE id=$1 FOR UPDATE', [id]))
          .rows[0];
        if (!b || b.driver_id !== actor.id) throw new ForbiddenException();
        if (b.status !== 'COMPLETED') throw new ConflictException('Complete trip first');
        await this.eligible(db, actor, b.vehicle_id);
        const p = (
          await db.query(
            "INSERT INTO payments(booking_id,amount_paise,method,status) VALUES($1,$2,'CASH','SUCCEEDED') RETURNING *",
            [id, b.fare_paise],
          )
        ).rows[0];
        await db.query(
          'INSERT INTO ledger_entries(payment_id,account,amount_paise) VALUES($1,$2,$3),($1,$4,$5)',
          [
            p.id,
            'driver_cash:' + actor.id,
            b.fare_paise,
            'passenger_cash:' + b.passenger_id,
            -b.fare_paise,
          ],
        );
        return p;
      }),
    );
  }
}
