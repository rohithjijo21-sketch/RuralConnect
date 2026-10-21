import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { pool, transaction } from './db.js';
import { plausible, type Actor } from './domain.js';

const fields = `b.*,r.category,r.pickup_label,r.dropoff_label,
ST_Y(r.pickup::geometry) pickup_lat,ST_X(r.pickup::geometry) pickup_lng,
ST_Y(r.dropoff::geometry) dropoff_lat,ST_X(r.dropoff::geometry) dropoff_lng,
v.registration,du.name driver_name,
CASE WHEN b.status IN ('ACCEPTED','ARRIVED','IN_PROGRESS') AND l.recorded_at BETWEEN now()-interval '60 seconds' AND now() THEN ST_Y(l.point::geometry) END driver_lat,
CASE WHEN b.status IN ('ACCEPTED','ARRIVED','IN_PROGRESS') AND l.recorded_at BETWEEN now()-interval '60 seconds' AND now() THEN ST_X(l.point::geometry) END driver_lng,
CASE WHEN b.status IN ('ACCEPTED','ARRIVED','IN_PROGRESS') THEN l.recorded_at END driver_recorded_at,
EXISTS(SELECT 1 FROM payments p WHERE p.booking_id=b.id AND p.status='SUCCEEDED') cash_recorded`;
const joins = `FROM private_bookings b JOIN ride_requests r ON r.id=b.request_id
LEFT JOIN vehicles v ON v.id=b.vehicle_id LEFT JOIN users du ON du.id=b.driver_id
LEFT JOIN driver_locations l ON l.user_id=b.driver_id`;

@Injectable()
export class PrivateRides {
  async expire() {
    // Expiry is enforced on reads and acceptance; no always-on paid worker required.
    await pool.query(`WITH expired AS (
      UPDATE private_bookings SET status='CANCELLED',version=version+1
      WHERE status='REQUESTED' AND created_at<now()-interval '3 minutes' RETURNING id)
      INSERT INTO booking_state_history(booking_id,from_state,to_state)
      SELECT id,'REQUESTED','CANCELLED' FROM expired`);
  }
  async quote(input: {
    pickup: { lat: number; lng: number };
    dropoff: { lat: number; lng: number };
    category: string;
  }) {
    const policy = (
      await pool.query(
        `SELECT * FROM fare_policies WHERE category=$1 AND (NOT beta_only OR $2) ORDER BY version DESC LIMIT 1`,
        [input.category, process.env.BETA_AUTH_ENABLED === 'true'],
      )
    ).rows[0];
    if (!policy)
      throw new ConflictException('Fares have not been configured for this vehicle type');
    const meters = Number(
      (
        await pool.query(
          `SELECT ST_Distance(ST_SetSRID(ST_MakePoint($1,$2),4326)::geography,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography) meters`,
          [input.pickup.lng, input.pickup.lat, input.dropoff.lng, input.dropoff.lat],
        )
      ).rows[0].meters,
    );
    if (meters < 50 || meters > 100000)
      throw new ConflictException('Choose distinct locations within 100 km');
    return {
      farePaise: policy.base_paise + Math.ceil(meters / 1000) * policy.per_km_paise,
      distanceMeters: Math.round(meters),
      distanceSource: 'STRAIGHT_LINE',
      betaPrice: policy.beta_only,
      method: 'CASH',
    };
  }
  async list(actor: Actor, as?: 'driver' | 'passenger') {
    await this.expire();
    return (
      await pool.query(
        `SELECT ${fields} ${joins} WHERE (b.passenger_id=$1 OR b.driver_id=$1) AND ($2::text IS NULL OR ($2='driver' AND b.driver_id=$1) OR ($2='passenger' AND b.passenger_id=$1)) ORDER BY b.created_at DESC LIMIT 100`,
        [actor.id, as ?? null],
      )
    ).rows;
  }
  async detail(actor: Actor, id: string) {
    await this.expire();
    const b = (
      await pool.query(
        `SELECT ${fields} ${joins} WHERE b.id=$1 AND (b.passenger_id=$2 OR b.driver_id=$2)`,
        [id, actor.id],
      )
    ).rows[0];
    if (!b) throw new NotFoundException();
    return b;
  }
  async availability(actor: Actor) {
    if (!actor.roles.includes('DRIVER')) throw new ForbiddenException();
    return (
      (
        await pool.query('SELECT online,verification FROM driver_profiles WHERE user_id=$1', [
          actor.id,
        ])
      ).rows[0] ?? { online: false, verification: 'PENDING' }
    );
  }
  async location(
    actor: Actor,
    input: { lat: number; lng: number; accuracyM: number; recordedAt: string },
  ) {
    if (!actor.roles.includes('DRIVER')) throw new ForbiddenException();
    return transaction(async (db) => {
      const d = (
        await db.query(
          `SELECT 1 FROM driver_profiles d JOIN users u ON u.id=d.user_id WHERE d.user_id=$1 AND d.online AND d.verification='APPROVED' AND NOT u.suspended AND u.deleted_at IS NULL FOR UPDATE OF d`,
          [actor.id],
        )
      ).rows[0];
      if (!d) throw new ForbiddenException('Go online with an approved driver account first');
      const previous = (
        await db.query(
          `SELECT ST_Y(point::geometry) lat,ST_X(point::geometry) lng,recorded_at at FROM driver_locations WHERE user_id=$1`,
          [actor.id],
        )
      ).rows[0];
      if (
        !plausible(previous ?? null, {
          lat: input.lat,
          lng: input.lng,
          at: new Date(input.recordedAt),
        })
      )
        throw new ConflictException('Location is outdated or implausible');
      await db.query(
        `INSERT INTO driver_locations(user_id,point,accuracy_m,recorded_at) VALUES($1,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,$4,$5) ON CONFLICT(user_id) DO UPDATE SET point=excluded.point,accuracy_m=excluded.accuracy_m,recorded_at=excluded.recorded_at`,
        [actor.id, input.lng, input.lat, input.accuracyM, input.recordedAt],
      );
      return { recorded: true };
    });
  }
  async offers(actor: Actor) {
    if (!actor.roles.includes('DRIVER')) throw new ForbiddenException();
    await this.expire();
    return (
      await pool.query(
        `SELECT b.id,b.fare_paise,b.created_at,r.category,r.pickup_label,r.dropoff_label,
      ST_Y(r.pickup::geometry) pickup_lat,ST_X(r.pickup::geometry) pickup_lng,
      ST_Y(r.dropoff::geometry) dropoff_lat,ST_X(r.dropoff::geometry) dropoff_lng,
      round(ST_Distance(l.point,r.pickup))::int pickup_distance_m
      FROM private_bookings b JOIN ride_requests r ON r.id=b.request_id
      JOIN driver_profiles d ON d.user_id=$1 AND d.online AND d.verification='APPROVED'
      JOIN driver_locations l ON l.user_id=d.user_id AND l.recorded_at BETWEEN now()-interval '60 seconds' AND now()
      JOIN users u ON u.id=d.user_id AND NOT u.suspended AND u.deleted_at IS NULL
      WHERE b.status='REQUESTED' AND b.passenger_id<>$1 AND b.created_at>=now()-interval '3 minutes'
      AND ST_DWithin(l.point,r.pickup,8000)
      AND EXISTS(SELECT 1 FROM vehicles v WHERE v.driver_id=$1 AND v.approved AND v.category=r.category)
      AND NOT EXISTS(SELECT 1 FROM private_bookings active WHERE active.driver_id=$1 AND active.status IN ('ACCEPTED','ARRIVED','IN_PROGRESS'))
      AND NOT EXISTS(SELECT 1 FROM private_offer_rejections x WHERE x.booking_id=b.id AND x.driver_id=$1)
      ORDER BY b.created_at LIMIT 20`,
        [actor.id],
      )
    ).rows;
  }
  async reject(actor: Actor, id: string) {
    if (!(await this.offers(actor)).some((b) => b.id === id)) throw new NotFoundException();
    await pool.query(
      'INSERT INTO private_offer_rejections(booking_id,driver_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
      [id, actor.id],
    );
    return { dismissed: true };
  }
  async confirmPickup(actor: Actor, id: string, version: number) {
    return transaction(async (db) => {
      const b = (await db.query('SELECT * FROM private_bookings WHERE id=$1 FOR UPDATE', [id]))
        .rows[0];
      if (!b || b.passenger_id !== actor.id) throw new NotFoundException();
      if (b.status !== 'ARRIVED' || b.version !== version)
        throw new ConflictException('Refresh this ride before confirming pickup');
      return (
        await db.query(
          'UPDATE private_bookings SET pickup_confirmed_at=now(),version=version+1 WHERE id=$1 RETURNING *',
          [id],
        )
      ).rows[0];
    });
  }
}
