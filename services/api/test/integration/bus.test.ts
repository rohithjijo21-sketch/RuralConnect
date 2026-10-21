import test from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../../src/db.js';
import { Bus } from '../../src/bus.js';
import { Bookings } from '../../src/bookings.js';
import { Auth } from '../../src/auth.js';
const enabled = process.env.RUN_DB_TESTS === '1';
test(
  'PostGIS bus service, isolation, notifications, GPS and concurrent seats',
  { skip: !enabled },
  async (t) => {
    t.after(() => pool.end());
    if (
      process.env.NODE_ENV === 'production' ||
      !process.env.DATABASE_URL?.includes('ruralconnect_test')
    )
      throw new Error('Use a disposable ruralconnect_test database');
    const bus = new Bus(),
      booking = new Bookings(),
      auth = new Auth();
    const op = (
      await pool.query("INSERT INTO operators(name) VALUES('TEST operator') RETURNING id")
    ).rows[0].id;
    async function user(n: number, role: string) {
      const u = (
        await pool.query('INSERT INTO users(phone) VALUES($1) RETURNING id', [
          '+91811111' + String(n).padStart(4, '0'),
        ])
      ).rows[0].id;
      await pool.query('INSERT INTO user_roles(user_id,role) VALUES($1,$2)', [u, role]);
      return { id: u, roles: [role] as any };
    }
    const operator = await user(1, 'OPERATOR'),
      crew = await user(2, 'BUS_CREW'),
      passenger = await user(3, 'PASSENGER'),
      outsider = await user(4, 'OPERATOR'),
      driver = await user(5, 'DRIVER'),
      otherPassenger = await user(6, 'PASSENGER');
    for (const u of [operator, crew])
      await pool.query('INSERT INTO operator_members(operator_id,user_id) VALUES($1,$2)', [
        op,
        u.id,
      ]);
    const vehicle = (
      await pool.query(
        "INSERT INTO vehicles(operator_id,registration,category,capacity,approved) VALUES($1,'TEST-BUS','BUS',30,true) RETURNING id",
        [op],
      )
    ).rows[0].id;
    const route = await bus.createRoute(operator, {
      operatorId: op,
      name: 'TEST route',
      stops: [
        { name: 'A', lat: 10, lng: 76, offsetMinutes: 0 },
        { name: 'B', lat: 10.01, lng: 76, offsetMinutes: 10 },
      ],
    });
    const service = await bus.createService(operator, {
      operatorId: op,
      routeVersionId: route.routeVersionId,
      vehicleId: vehicle,
      crewId: crew.id,
      departureAt: new Date().toISOString(),
      serviceDate: new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Asia/Kolkata',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).format(new Date()),
    });
    await assert.rejects(
      bus.status(outsider, service.id, {
        status: 'CANCELLED',
        reason: 'bad actor',
        delayMinutes: 0,
        version: 1,
      }),
    );
    await pool.query('INSERT INTO notification_subscriptions(user_id,trip_id) VALUES($1,$2)', [
      passenger.id,
      service.id,
    ]);
    await bus.status(crew, service.id, {
      status: 'BOARDING',
      reason: 'Ready',
      delayMinutes: 0,
      version: 1,
    });
    await bus.status(crew, service.id, {
      status: 'RUNNING',
      reason: 'Started',
      delayMinutes: 0,
      version: 2,
    });
    await bus.location(crew, service.id, {
      lat: 10,
      lng: 76,
      accuracyM: 10,
      recordedAt: new Date().toISOString(),
    });
    const detail = await bus.detail(service.id);
    assert.equal(detail.locationQuality, 'LIVE');
    assert.equal(detail.stops.length, 2);
    assert.equal(detail.stops[0].lat, 10);
    assert.equal(detail.stops[1].lng, 76);
    const searched = await bus.search(
      new Intl.DateTimeFormat('en-CA', {
        timeZone: 'Asia/Kolkata',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
      }).format(new Date()),
      'A',
      'B',
    );
    assert.equal(searched.find((t) => t.id === service.id)?.stops[0].lat, 10);
    await bus.status(crew, service.id, {
      status: 'DELAYED',
      reason: 'Traffic',
      delayMinutes: 10,
      version: 3,
    });
    assert.equal((await bus.detail(service.id)).delay_minutes, 10);
    assert.ok(
      (await pool.query('SELECT 1 FROM notifications WHERE user_id=$1', [passenger.id])).rowCount,
    );
    await bus.status(crew, service.id, {
      status: 'CANCELLED',
      reason: 'Breakdown',
      delayMinutes: 0,
      version: 4,
    });
    assert.equal((await bus.detail(service.id)).lat, null);
    await assert.rejects(
      bus.status(crew, service.id, {
        status: 'SCHEDULED',
        reason: 'Restore',
        delayMinutes: 0,
        version: 5,
      }),
    );
    await bus.status(operator, service.id, {
      status: 'SCHEDULED',
      reason: 'Operator reinstatement',
      delayMinutes: 0,
      version: 5,
    });
    await pool.query("INSERT INTO driver_profiles(user_id,verification) VALUES($1,'APPROVED')", [
      driver.id,
    ]);
    const auto = (
      await pool.query(
        "INSERT INTO vehicles(driver_id,registration,category,capacity,approved) VALUES($1,'TEST-AUTO','AUTO',1,true) RETURNING id",
        [driver.id],
      )
    ).rows[0].id;
    const shared = await booking.sharedCreate(driver, {
      vehicleId: auto,
      departureAt: new Date(Date.now() + 3600000).toISOString(),
      capacity: 1,
      farePaise: 2000,
      stops: [
        { name: 'A', lat: 10, lng: 76 },
        { name: 'B', lat: 10.01, lng: 76 },
      ],
    });
    const input = { seats: 1, pickupSequence: 0, dropoffSequence: 1 };
    const results = await Promise.allSettled([
      booking.reserve(passenger, shared.id, input, 'request-a'),
      booking.reserve(otherPassenger, shared.id, input, 'request-b'),
    ]);
    assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
    assert.equal(results.filter((r) => r.status === 'rejected').length, 1);
    const winner = results[0].status === 'fulfilled' ? passenger : otherPassenger,
      key = results[0].status === 'fulfilled' ? 'request-a' : 'request-b';
    const replay = await booking.reserve(winner, shared.id, input, key);
    assert.ok(replay.id);
    assert.equal(
      (
        await pool.query('SELECT count(*)::int n FROM seat_reservations WHERE trip_id=$1', [
          shared.id,
        ])
      ).rows[0].n,
      1,
    );

    assert.equal((await booking.sharedList()).find((t) => t.id === shared.id).availableSeats, 0);
    const reservations = await booking.driverShared(driver);
    assert.equal(reservations.find((t) => t.id === shared.id).reservations.length, 1);
    await assert.rejects(booking.boarding(passenger, replay.id, 'BOARDED'));
    await booking.sharedStatus(driver, shared.id, 'BOARDING');
    await assert.rejects(booking.boarding(driver, replay.id, 'NO_SHOW'));
    await booking.boarding(driver, replay.id, 'BOARDED');
    await booking.sharedStatus(driver, shared.id, 'IN_PROGRESS');
    await booking.sharedStatus(driver, shared.id, 'COMPLETED');
    assert.equal(
      (await pool.query('SELECT status FROM seat_reservations WHERE id=$1', [replay.id])).rows[0]
        .status,
      'COMPLETED',
    );
    await assert.rejects(auth.actor('Bearer invalid'));
  },
);
