import test from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../../src/db.js';
import { BusOwner } from '../../src/bus-owner.js';
import { Bus } from '../../src/bus.js';
test(
  'Bus owner onboarding, fleet isolation, pending approval and recurring dated trips',
  { skip: process.env.RUN_DB_TESTS !== '1' },
  async (t) => {
    t.after(() => pool.end());
    if (
      process.env.NODE_ENV === 'production' ||
      !process.env.DATABASE_URL?.includes('ruralconnect_test')
    )
      throw Error('Disposable database required');
    async function actor(phone: string, roles: any[]) {
      const u = (await pool.query('INSERT INTO users(phone) VALUES($1) RETURNING id', [phone]))
        .rows[0];
      for (const role of roles)
        await pool.query('INSERT INTO user_roles(user_id,role) VALUES($1,$2)', [u.id, role]);
      return { ...u, roles };
    }
    const a = await actor('+918222220001', ['BUS_CREW']),
      b = await actor('+918222220002', ['BUS_CREW']),
      passenger = await actor('+918222220003', ['PASSENGER']);
    const owner = new BusOwner(),
      bus = new Bus();
    assert.equal((await owner.workspace(a)).owner, null);
    await assert.rejects(owner.register(passenger, 'No owner access'));
    const op = await owner.register(a, 'TEST owner');
    assert.equal(op.status, 'PENDING');
    assert.equal((await owner.register(a, 'retry')).operator_id, op.operator_id);
    await owner.register(b, 'TEST other owner');
    const v = await owner.vehicle(a, 'TEST-OWNER-BUS', 32);
    assert.equal(v.approved, false);
    const r = await bus.createRoute(a, {
      operatorId: op.operator_id,
      name: 'TEST owner route',
      stops: [
        { name: 'First', lat: 10, lng: 76, offsetMinutes: 0 },
        { name: 'Last', lat: 10.01, lng: 76.01, offsetMinutes: 30 },
      ],
    });
    await assert.rejects(
      bus.createRoute(b, { operatorId: op.operator_id, name: 'cross tenant', stops: [] }),
    );
    const input = {
      name: 'Weekday service',
      vehicleId: v.id,
      routeVersionId: r.routeVersionId,
      crewId: a.id,
      departureTime: '09:00',
      startDate: '2030-01-07',
      endDate: '2030-01-09',
      weekdays: [1, 2, 3],
      excludedDates: ['2030-01-08'],
    };
    await assert.rejects(owner.plan(b, input));
    const p = await owner.plan(a, input);
    await assert.rejects(owner.publish(a, p.id, '2030-01-07', '2030-01-09'));
    await pool.query("UPDATE bus_owners SET status='APPROVED' WHERE user_id=$1", [a.id]);
    await pool.query('UPDATE operators SET verified=true WHERE id=$1', [op.operator_id]);
    await assert.rejects(owner.publish(a, p.id, '2030-01-07', '2030-01-09'));
    await pool.query('UPDATE vehicles SET approved=true WHERE id=$1', [v.id]);
    const first = await owner.publish(a, p.id, '2030-01-07', '2030-01-09');
    assert.equal(first.trips.length, 2);
    const retry = await owner.publish(a, p.id, '2030-01-07', '2030-01-09');
    assert.deepEqual(
      retry.trips.map((x) => x.id),
      first.trips.map((x) => x.id),
    );
    assert.equal(
      (await pool.query('SELECT count(*)::int n FROM bus_plan_instances WHERE plan_id=$1', [p.id]))
        .rows[0].n,
      2,
    );
    await assert.rejects(owner.publish(b, p.id, '2030-01-07', '2030-01-09'));
    assert.equal((await owner.workspace(b)).vehicles.length, 0);
    const extra = {
      operatorId: op.operator_id,
      routeVersionId: r.routeVersionId,
      vehicleId: v.id,
      crewId: a.id,
      serviceDate: '2030-01-07',
      departureAt: '2030-01-07T09:15:00+05:30',
    };
    await assert.rejects(bus.createService(a, extra), /overlapping/);
    await bus.createService(a, { ...extra, departureAt: '2030-01-07T09:30:00+05:30' });
    const competing = await Promise.allSettled([
      bus.createService(a, {
        ...extra,
        serviceDate: '2030-01-10',
        departureAt: '2030-01-10T09:00:00+05:30',
      }),
      bus.createService(a, {
        ...extra,
        serviceDate: '2030-01-10',
        departureAt: '2030-01-10T09:15:00+05:30',
      }),
    ]);
    assert.equal(competing.filter((x) => x.status === 'fulfilled').length, 1);
    const anotherBus = await owner.vehicle(a, 'TEST-OWNER-SECOND', 32);
    await pool.query('UPDATE vehicles SET approved=true WHERE id=$1', [anotherBus.id]);
    await assert.rejects(
      bus.createService(a, { ...extra, vehicleId: anotherBus.id }),
      /overlapping/,
    );
    const original = first.trips[0];
    const cancelled = await bus.status(a, original.id, {
      status: 'CANCELLED',
      reason: 'TEST cancellation',
      delayMinutes: 0,
      version: original.version,
    });
    const replacement = await bus.createService(a, {
      ...extra,
      departureAt: '2030-01-07T09:00:00+05:30',
    });
    await assert.rejects(
      bus.status(a, original.id, {
        status: 'SCHEDULED',
        reason: 'TEST reinstate conflict',
        delayMinutes: 0,
        version: cancelled.version,
      }),
      /overlapping/,
    );
    await bus.status(a, replacement.id, {
      status: 'CANCELLED',
      reason: 'TEST release replacement',
      delayMinutes: 0,
      version: replacement.version,
    });
    await pool.query('UPDATE vehicles SET approved=false WHERE id=$1', [v.id]);
    await assert.rejects(
      bus.status(a, original.id, {
        status: 'SCHEDULED',
        reason: 'TEST revoked bus',
        delayMinutes: 0,
        version: cancelled.version,
      }),
      /approved bus/,
    );
    await pool.query('UPDATE vehicles SET approved=true WHERE id=$1', [v.id]);
    const restored = await bus.status(a, original.id, {
      status: 'SCHEDULED',
      reason: 'TEST safe reinstatement',
      delayMinutes: 0,
      version: cancelled.version,
    });
    assert.equal(restored.status, 'SCHEDULED');
    const cancelledAgain = await bus.status(a, original.id, {
      status: 'CANCELLED',
      reason: 'TEST concurrent reinstatement',
      delayMinutes: 0,
      version: restored.version,
    });
    const restoreRace = await Promise.allSettled([
      bus.status(a, original.id, {
        status: 'SCHEDULED',
        reason: 'TEST racing publication',
        delayMinutes: 0,
        version: cancelledAgain.version,
      }),
      bus.createService(a, { ...extra, departureAt: '2030-01-07T09:00:00+05:30' }),
    ]);
    assert.equal(restoreRace.filter((result) => result.status === 'fulfilled').length, 1);
    assert.equal(restoreRace.filter((result) => result.status === 'rejected').length, 1);
    assert.equal(
      (
        await pool.query(
          'SELECT count(*)::int n FROM driver_assignments WHERE trip_id=$1 AND user_id=$2',
          [first.trips[0].id, a.id],
        )
      ).rows[0].n,
      1,
    );
  },
);
