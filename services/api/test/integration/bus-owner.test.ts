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
