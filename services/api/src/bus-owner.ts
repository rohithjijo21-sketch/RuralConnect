import {
  Injectable,
  ForbiddenException,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { pool, transaction } from './db.js';
import { Bus } from './bus.js';
import type { Actor } from './domain.js';

@Injectable()
export class BusOwner {
  async own(actor: Actor, db: any = pool) {
    if (!actor.roles.includes('BUS_CREW')) throw new ForbiddenException('Bus crew access required');
    const row = (
      await db.query(
        'SELECT b.*,o.name FROM bus_owners b JOIN operators o ON o.id=b.operator_id WHERE b.user_id=$1',
        [actor.id],
      )
    ).rows[0];
    if (!row) throw new NotFoundException('Create your owner workspace first');
    if (row.status === 'REJECTED')
      throw new ForbiddenException('Owner application requires review');
    return row;
  }
  async register(actor: Actor, name: string) {
    if (!actor.roles.includes('BUS_CREW')) throw new ForbiddenException();
    return transaction(async (db) => {
      await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [
        'bus-owner:' + actor.id,
      ]);
      const existing = (await db.query('SELECT * FROM bus_owners WHERE user_id=$1', [actor.id]))
        .rows[0];
      if (existing) return existing;
      const op = (await db.query('INSERT INTO operators(name) VALUES($1) RETURNING id', [name]))
        .rows[0];
      await db.query('INSERT INTO operator_members(operator_id,user_id) VALUES($1,$2)', [
        op.id,
        actor.id,
      ]);
      const row = (
        await db.query('INSERT INTO bus_owners(user_id,operator_id) VALUES($1,$2) RETURNING *', [
          actor.id,
          op.id,
        ])
      ).rows[0];
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id) VALUES($1,$2,'owner.apply',$2)",
        [actor.id, op.id],
      );
      return row;
    });
  }
  async workspace(actor: Actor) {
    const exists = (await pool.query('SELECT 1 FROM bus_owners WHERE user_id=$1', [actor.id]))
      .rowCount;
    if (!actor.roles.includes('BUS_CREW')) throw new ForbiddenException();
    if (!exists) return { owner: null, vehicles: [], routes: [], plans: [], crew: [] };
    const owner = await this.own(actor);
    const vehicles = (
      await pool.query(
        "SELECT id,registration,capacity,approved FROM vehicles WHERE operator_id=$1 AND category='BUS' ORDER BY registration",
        [owner.operator_id],
      )
    ).rows;
    const routes = (
      await pool.query(
        "SELECT rv.id,r.name,(SELECT json_agg(json_build_object('name',s.name,'offsetMinutes',rs.offset_minutes,'lat',ST_Y(s.point::geometry),'lng',ST_X(s.point::geometry)) ORDER BY rs.sequence) FROM route_stops rs JOIN bus_stops s ON s.id=rs.stop_id WHERE rs.route_version_id=rv.id) stops FROM route_versions rv JOIN bus_routes r ON r.id=rv.route_id WHERE r.operator_id=$1 ORDER BY r.name",
        [owner.operator_id],
      )
    ).rows;
    const plans = (
      await pool.query(
        'SELECT p.*, (SELECT count(*) FROM bus_plan_instances i WHERE i.plan_id=p.id) published_trips FROM bus_service_plans p WHERE p.operator_id=$1 ORDER BY p.created_at DESC',
        [owner.operator_id],
      )
    ).rows;
    const crew = (
      await pool.query(
        "SELECT u.id,u.name FROM users u JOIN operator_members m ON m.user_id=u.id JOIN user_roles r ON r.user_id=u.id WHERE m.operator_id=$1 AND r.role='BUS_CREW' AND NOT u.suspended AND u.deleted_at IS NULL",
        [owner.operator_id],
      )
    ).rows;
    return { owner, vehicles, routes, plans, crew };
  }
  async vehicle(actor: Actor, registration: string, capacity: number) {
    return transaction(async (db) => {
      const o = await this.own(actor, db);
      const v = (
        await db.query(
          "INSERT INTO vehicles(operator_id,registration,category,capacity) VALUES($1,$2,'BUS',$3) RETURNING id,registration,capacity,approved",
          [o.operator_id, registration.toUpperCase(), capacity],
        )
      ).rows[0];
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id) VALUES($1,$2,'bus.register',$3)",
        [actor.id, o.operator_id, v.id],
      );
      return v;
    });
  }
  async plan(actor: Actor, input: any, previousPlanId?: string) {
    return transaction(async (db) => {
      const o = await this.own(actor, db);
      if (previousPlanId) {
        const previous = (
          await db.query('SELECT id FROM bus_service_plans WHERE id=$1 AND operator_id=$2', [
            previousPlanId,
            o.operator_id,
          ])
        ).rows[0];
        if (!previous) throw new NotFoundException('Timetable not found in your workspace');
      }
      const ok = (
        await db.query(
          "SELECT 1 FROM vehicles v JOIN bus_routes r ON r.operator_id=v.operator_id JOIN route_versions rv ON rv.route_id=r.id JOIN operator_members m ON m.operator_id=v.operator_id JOIN user_roles ur ON ur.user_id=m.user_id AND ur.role='BUS_CREW' WHERE v.id=$1 AND rv.id=$2 AND v.operator_id=$3 AND m.user_id=$4 AND v.category='BUS'",
          [input.vehicleId, input.routeVersionId, o.operator_id, input.crewId],
        )
      ).rowCount;
      if (!ok) throw new ForbiddenException('Choose your own bus, route and authorised crew');
      if (input.endDate < input.startDate)
        throw new BadRequestException('End date precedes start date');
      const p = (
        await db.query(
          'INSERT INTO bus_service_plans(operator_id,vehicle_id,route_version_id,crew_id,name,departure_time,start_date,end_date,weekdays,excluded_dates) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *',
          [
            o.operator_id,
            input.vehicleId,
            input.routeVersionId,
            input.crewId,
            input.name,
            input.departureTime,
            input.startDate,
            input.endDate,
            input.weekdays,
            input.excludedDates,
          ],
        )
      ).rows[0];
      await db.query(
        "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id) VALUES($1,$2,'timetable.create',$3)",
        [actor.id, o.operator_id, p.id],
      );
      if (previousPlanId)
        await db.query(
          "INSERT INTO audit_logs(actor_id,operator_id,action,resource_id,detail) VALUES($1,$2,'timetable.revise',$3,$4)",
          [actor.id, o.operator_id, p.id, JSON.stringify({ previousPlanId })],
        );
      return p;
    });
  }
  async publish(actor: Actor, planId: string, fromDate: string, toDate: string) {
    const o = await this.own(actor);
    if (o.status !== 'APPROVED')
      throw new ForbiddenException('Owner approval is required before publishing');
    const p = (
      await pool.query('SELECT * FROM bus_service_plans WHERE id=$1 AND operator_id=$2', [
        planId,
        o.operator_id,
      ])
    ).rows[0];
    if (!p) throw new NotFoundException();
    if (toDate < fromDate || (Date.parse(toDate) - Date.parse(fromDate)) / 86400000 > 30)
      throw new BadRequestException('Publish at most 31 calendar days at a time');
    const days = (
      await pool.query(
        "SELECT d::date::text AS service_day FROM generate_series($1::date,$2::date,interval '1 day') d WHERE d::date BETWEEN $3::date AND $4::date AND extract(isodow from d)::integer=ANY($5::integer[]) AND NOT(d::date=ANY($6::date[])) ORDER BY d LIMIT 32",
        [fromDate, toDate, p.start_date, p.end_date, p.weekdays, p.excluded_dates],
      )
    ).rows;
    if (
      toDate < fromDate ||
      days.length > 31 ||
      (Date.parse(toDate) - Date.parse(fromDate)) / 86400000 > 30
    )
      throw new BadRequestException('Publish at most 31 calendar days at a time');
    const bus = new Bus();
    const trips = [];
    for (const d of days)
      trips.push(
        await bus.createService(actor, {
          operatorId: o.operator_id,
          routeVersionId: p.route_version_id,
          vehicleId: p.vehicle_id,
          crewId: p.crew_id,
          serviceDate: d.service_day,
          departureAt: d.service_day + 'T' + p.departure_time + '+05:30',
          planId: p.id,
        }),
      );
    return { trips };
  }
}
