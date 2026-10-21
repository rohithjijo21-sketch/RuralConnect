import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  ConflictException,
  BadRequestException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { pool, transaction } from './db.js';
import { canTransition, fresh, plausible, type Actor, type BusState } from './domain.js';
@Injectable()
export class Bus {
  async operator(db: PoolClient, actor: Actor, operatorId: string) {
    if (actor.roles.includes('ADMIN')) return;
    if (
      actor.roles.includes('BUS_CREW') &&
      (
        await db.query(
          "SELECT 1 FROM bus_owners b JOIN operators o ON o.id=b.operator_id WHERE b.user_id=$1 AND b.operator_id=$2 AND b.status='APPROVED' AND o.verified",
          [actor.id, operatorId],
        )
      ).rowCount
    )
      return;
    if (
      !actor.roles.includes('OPERATOR') ||
      !(
        await db.query('SELECT 1 FROM operator_members WHERE operator_id=$1 AND user_id=$2', [
          operatorId,
          actor.id,
        ])
      ).rowCount
    )
      throw new ForbiddenException();
  }
  async authorized(db: PoolClient, actor: Actor, trip: any) {
    const op =
      actor.roles.includes('ADMIN') ||
      (actor.roles.includes('BUS_CREW') &&
        !!(
          await db.query(
            "SELECT 1 FROM bus_owners b JOIN operators o ON o.id=b.operator_id WHERE b.user_id=$1 AND b.operator_id=$2 AND b.status='APPROVED' AND o.verified",
            [actor.id, trip.operator_id],
          )
        ).rowCount) ||
      (actor.roles.includes('OPERATOR') &&
        !!(
          await db.query('SELECT 1 FROM operator_members WHERE operator_id=$1 AND user_id=$2', [
            trip.operator_id,
            actor.id,
          ])
        ).rowCount);
    if (op) return true;
    const today = (
      await db.query(
        "SELECT 1 FROM trip_instances WHERE id=$1 AND service_date=(now() AT TIME ZONE 'Asia/Kolkata')::date",
        [trip.id],
      )
    ).rowCount;
    if (!today) throw new ForbiddenException('Crew may update only current-day assigned services');
    if (
      !actor.roles.includes('BUS_CREW') ||
      !(
        await db.query('SELECT 1 FROM driver_assignments WHERE trip_id=$1 AND user_id=$2', [
          trip.id,
          actor.id,
        ])
      ).rowCount
    )
      throw new ForbiddenException();
    return false;
  }
  async event(db: PoolClient, trip: any, topic: string, payload: unknown) {
    const e = (
      await db.query(
        'INSERT INTO events(topic,resource_id,version,payload) VALUES($1,$2,$3,$4) RETURNING id',
        [topic, trip.id, trip.version, JSON.stringify(payload)],
      )
    ).rows[0];
    if (topic !== 'bus.location.v1')
      await db.query(
        'INSERT INTO notifications(user_id,event_id) SELECT user_id,$1 FROM notification_subscriptions WHERE trip_id=$2 ON CONFLICT DO NOTHING',
        [e.id, trip.id],
      );
  }
  async search(date: string, origin?: string, destination?: string, operatorId?: string) {
    const { rows } = await pool.query(
      "SELECT t.*,r.name route_name,v.registration,ST_Y(l.point::geometry) lat,ST_X(l.point::geometry) lng,l.recorded_at, (SELECT json_agg(json_build_object('id',s.id,'name',s.name,'sequence',rs.sequence,'offsetMinutes',rs.offset_minutes) ORDER BY rs.sequence) FROM route_stops rs JOIN bus_stops s ON s.id=rs.stop_id WHERE rs.route_version_id=t.route_version_id) stops FROM trip_instances t JOIN route_versions rv ON rv.id=t.route_version_id JOIN bus_routes r ON r.id=rv.route_id JOIN vehicles v ON v.id=t.vehicle_id LEFT JOIN vehicle_locations l ON l.trip_id=t.id WHERE t.service_date=$1::date AND ($4::uuid IS NULL OR t.operator_id=$4) AND ($2::text IS NULL OR EXISTS(SELECT 1 FROM route_stops a JOIN bus_stops sa ON sa.id=a.stop_id JOIN route_stops b ON b.route_version_id=a.route_version_id AND b.sequence>a.sequence JOIN bus_stops sb ON sb.id=b.stop_id WHERE a.route_version_id=t.route_version_id AND sa.name ILIKE '%'||$2||'%' AND sb.name ILIKE '%'||$3||'%')) ORDER BY t.departure_at LIMIT 200",
      [date, origin ?? null, destination ?? null, operatorId ?? null],
    );
    return rows.map(this.present);
  }
  present(row: any) {
    const live =
      fresh(row.recorded_at) && ['RUNNING', 'DELAYED', 'STOPPED', 'DIVERTED'].includes(row.status);
    return {
      ...row,
      lat: live ? row.lat : null,
      lng: live ? row.lng : null,
      locationQuality: live ? 'LIVE' : row.recorded_at ? 'STALE' : 'UNAVAILABLE',
      timeSource: 'SCHEDULED',
      estimatedDelayMinutes: row.delay_minutes,
      eta: null,
    };
  }
  async detail(id: string) {
    const { rows } = await pool.query(
      'SELECT t.*,r.name route_name,v.registration,ST_Y(l.point::geometry) lat,ST_X(l.point::geometry) lng,l.recorded_at FROM trip_instances t JOIN route_versions rv ON rv.id=t.route_version_id JOIN bus_routes r ON r.id=rv.route_id JOIN vehicles v ON v.id=t.vehicle_id LEFT JOIN vehicle_locations l ON l.trip_id=t.id WHERE t.id=$1',
      [id],
    );
    if (!rows[0]) throw new NotFoundException();
    return this.present(rows[0]);
  }
  async status(
    actor: Actor,
    id: string,
    input: { status: BusState; reason: string; delayMinutes: number; version: number },
  ) {
    return transaction(async (db) => {
      const t = (await db.query('SELECT * FROM trip_instances WHERE id=$1 FOR UPDATE', [id]))
        .rows[0];
      if (!t) throw new NotFoundException();
      const op = await this.authorized(db, actor, t);
      if (t.version !== input.version) throw new ConflictException('Refresh trip; version changed');
      if (!canTransition(t.status, input.status, op))
        throw new ConflictException('Invalid trip transition');
      const updated = (
        await db.query(
          'UPDATE trip_instances SET status=$1,delay_minutes=$2,version=version+1 WHERE id=$3 RETURNING *',
          [input.status, input.status === 'DELAYED' ? input.delayMinutes : 0, id],
        )
      ).rows[0];
      await db.query(
        'INSERT INTO service_incidents(trip_id,actor_id,kind,reason,delay_minutes) VALUES($1,$2,$3,$4,$5)',
        [id, actor.id, input.status, input.reason, input.delayMinutes],
      );
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id,detail) VALUES($1,$2,'bus.status',$3,$4)",
        [
          actor.id,
          t.operator_id,
          id,
          JSON.stringify({ from: t.status, to: input.status, reason: input.reason }),
        ],
      );
      await this.event(db, updated, 'bus.status.v1', {
        tripId: id,
        status: updated.status,
        delayMinutes: updated.delay_minutes,
        version: updated.version,
      });
      return updated;
    });
  }
  async location(
    actor: Actor,
    id: string,
    input: { lat: number; lng: number; accuracyM: number; recordedAt: string },
  ) {
    return transaction(async (db) => {
      const t = (await db.query('SELECT * FROM trip_instances WHERE id=$1 FOR UPDATE', [id]))
        .rows[0];
      if (!t) throw new NotFoundException();
      await this.authorized(db, actor, t);
      if (!['RUNNING', 'DELAYED', 'STOPPED', 'DIVERTED'].includes(t.status))
        throw new ConflictException('Tracking requires an active service');
      const last = (
        await db.query(
          'SELECT ST_Y(point::geometry) lat,ST_X(point::geometry) lng,recorded_at at FROM vehicle_locations WHERE trip_id=$1',
          [id],
        )
      ).rows[0];
      const next = { lat: input.lat, lng: input.lng, at: new Date(input.recordedAt) };
      if (!plausible(last ?? null, next))
        throw new BadRequestException('Stale, out-of-order or implausible location');
      await db.query(
        'INSERT INTO vehicle_locations(trip_id,point,accuracy_m,recorded_at) VALUES($1,ST_SetSRID(ST_MakePoint($2,$3),4326)::geography,$4,$5) ON CONFLICT(trip_id) DO UPDATE SET point=EXCLUDED.point,accuracy_m=EXCLUDED.accuracy_m,recorded_at=EXCLUDED.recorded_at,received_at=now()',
        [id, input.lng, input.lat, input.accuracyM, input.recordedAt],
      );
      await db.query(
        'INSERT INTO vehicle_location_history(trip_id,point,recorded_at) SELECT trip_id,point,recorded_at FROM vehicle_locations WHERE trip_id=$1',
        [id],
      );
      await this.event(db, t, 'bus.location.v1', { tripId: id, ...input });
      return { accepted: true };
    });
  }
  async createRoute(
    actor: Actor,
    input: {
      operatorId: string;
      name: string;
      stops: { name: string; lat: number; lng: number; offsetMinutes: number }[];
    },
  ) {
    return transaction(async (db) => {
      const setupOwner =
        actor.roles.includes('BUS_CREW') &&
        (
          await db.query(
            "SELECT 1 FROM bus_owners WHERE user_id=$1 AND operator_id=$2 AND status IN ('PENDING','APPROVED')",
            [actor.id, input.operatorId],
          )
        ).rowCount;
      if (!setupOwner) await this.operator(db, actor, input.operatorId);
      if (!input.stops.length || input.stops[0].offsetMinutes !== 0)
        throw new BadRequestException('The first stop must have a zero minute offset');
      for (let i = 1; i < input.stops.length; i++)
        if (input.stops[i].offsetMinutes <= input.stops[i - 1].offsetMinutes)
          throw new BadRequestException('Stop offsets must increase');
      const r = (
        await db.query('INSERT INTO bus_routes(operator_id,name) VALUES($1,$2) RETURNING id', [
          input.operatorId,
          input.name,
        ])
      ).rows[0];
      const rv = (
        await db.query('INSERT INTO route_versions(route_id,version) VALUES($1,1) RETURNING id', [
          r.id,
        ])
      ).rows[0];
      for (const [i, s] of input.stops.entries()) {
        const stop = (
          await db.query(
            'INSERT INTO bus_stops(operator_id,name,point) VALUES($1,$2,ST_SetSRID(ST_MakePoint($3,$4),4326)::geography) RETURNING id',
            [input.operatorId, s.name, s.lng, s.lat],
          )
        ).rows[0];
        await db.query(
          'INSERT INTO route_stops(route_version_id,stop_id,sequence,offset_minutes) VALUES($1,$2,$3,$4)',
          [rv.id, stop.id, i, s.offsetMinutes],
        );
      }
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id) VALUES($1,$2,'route.create',$3)",
        [actor.id, input.operatorId, r.id],
      );
      return { routeId: r.id, routeVersionId: rv.id };
    });
  }
  async createService(
    actor: Actor,
    input: {
      operatorId: string;
      routeVersionId: string;
      vehicleId: string;
      crewId: string;
      departureAt: string;
      serviceDate: string;
      planId?: string;
    },
  ) {
    return transaction(async (db) => {
      await this.operator(db, actor, input.operatorId);
      if (input.planId) {
        const plan = (
          await db.query(
            'SELECT id FROM bus_service_plans WHERE id=$1 AND operator_id=$2 FOR UPDATE',
            [input.planId, input.operatorId],
          )
        ).rows[0];
        if (!plan) throw new ForbiddenException();
        const existing = (
          await db.query(
            'SELECT t.* FROM bus_plan_instances i JOIN trip_instances t ON t.id=i.trip_id WHERE i.plan_id=$1 AND i.service_date=$2',
            [input.planId, input.serviceDate],
          )
        ).rows[0];
        if (existing) return existing;
      }
      const serviceDate = (
        await db.query("SELECT ($1::timestamptz AT TIME ZONE 'Asia/Kolkata')::date::text d", [
          input.departureAt,
        ])
      ).rows[0].d;
      if (serviceDate !== input.serviceDate)
        throw new BadRequestException('Service date must match Kerala departure date');
      const ok = (
        await db.query(
          "SELECT 1 FROM route_versions rv JOIN bus_routes r ON r.id=rv.route_id JOIN vehicles v ON v.operator_id=r.operator_id JOIN operator_members m ON m.operator_id=r.operator_id JOIN user_roles ur ON ur.user_id=m.user_id AND ur.role='BUS_CREW' WHERE rv.id=$1 AND r.operator_id=$2 AND v.id=$3 AND v.approved AND v.category='BUS' AND m.user_id=$4",
          [input.routeVersionId, input.operatorId, input.vehicleId, input.crewId],
        )
      ).rowCount;
      if (!ok)
        throw new ForbiddenException(
          'Route, approved bus and authorised crew must belong to this operator',
        );
      // Serialize on both resources so two plans cannot double-book one bus or
      // crew member, including concurrent publications from different plans.
      const lockedBus = (
        await db.query('SELECT approved FROM vehicles WHERE id=$1 FOR UPDATE', [input.vehicleId])
      ).rows[0];
      const lockedCrew = (
        await db.query('SELECT suspended,deleted_at FROM users WHERE id=$1 FOR UPDATE', [
          input.crewId,
        ])
      ).rows[0];
      if (!lockedBus?.approved || !lockedCrew || lockedCrew.suspended || lockedCrew.deleted_at)
        throw new ForbiddenException('Bus approval and active crew access are required');
      const duration = (
        await db.query(
          'SELECT coalesce(max(offset_minutes),0)::int minutes FROM route_stops WHERE route_version_id=$1',
          [input.routeVersionId],
        )
      ).rows[0].minutes;
      if (duration <= 0)
        throw new BadRequestException('Route must have a positive scheduled duration');
      const conflict = (
        await db.query(
          "SELECT 1 FROM trip_instances t WHERE t.status<>'CANCELLED' AND (t.vehicle_id=$1 OR EXISTS(SELECT 1 FROM driver_assignments a WHERE a.trip_id=t.id AND a.user_id=$2)) AND t.departure_at < $3::timestamptz + $4::int * interval '1 minute' AND $3::timestamptz < t.departure_at + (SELECT coalesce(max(offset_minutes),0) * interval '1 minute' FROM route_stops WHERE route_version_id=t.route_version_id) LIMIT 1",
          [input.vehicleId, input.crewId, input.departureAt, duration],
        )
      ).rowCount;
      if (conflict)
        throw new ConflictException('Bus or crew already has an overlapping scheduled trip');
      const t = (
        await db.query(
          'INSERT INTO trip_instances(operator_id,route_version_id,vehicle_id,service_date,departure_at) VALUES($1,$2,$3,$4,$5) RETURNING *',
          [
            input.operatorId,
            input.routeVersionId,
            input.vehicleId,
            input.serviceDate,
            input.departureAt,
          ],
        )
      ).rows[0];
      await db.query(
        "INSERT INTO driver_assignments(trip_id,user_id,duty) VALUES($1,$2,'DRIVER')",
        [t.id, input.crewId],
      );
      await db.query('INSERT INTO vehicle_assignments(vehicle_id,trip_id) VALUES($1,$2)', [
        input.vehicleId,
        t.id,
      ]);
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id) VALUES($1,$2,'service.create',$3)",
        [actor.id, input.operatorId, t.id],
      );
      await this.event(db, t, 'bus.created.v1', { tripId: t.id, status: t.status });
      if (input.planId)
        await db.query(
          'INSERT INTO bus_plan_instances(plan_id,service_date,trip_id) VALUES($1,$2,$3)',
          [input.planId, input.serviceDate, t.id],
        );
      return t;
    });
  }
}
