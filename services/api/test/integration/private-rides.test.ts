import test from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../../src/db.js';
import { Bookings } from '../../src/bookings.js';
import { PrivateRides } from '../../src/private-rides.js';
import type { Actor } from '../../src/domain.js';

test(
  'Private ride matching, isolation, acceptance race, pickup confirmation, tracking and expiry',
  { skip: process.env.RUN_DB_TESTS !== '1' },
  async (t) => {
    t.after(() => pool.end());
    if (
      process.env.NODE_ENV === 'production' ||
      !process.env.DATABASE_URL?.includes('ruralconnect_test')
    )
      throw Error('Disposable database required');
    await pool.query(
      "INSERT INTO fare_policies(category,base_paise,per_km_paise,version) VALUES('AUTO',3000,1500,100)",
    );
    const rides = new PrivateRides(),
      bookings = new Bookings();
    const actors: Actor[] = [];
    for (let i = 0; i < 5; i++) {
      const u = (
        await pool.query('INSERT INTO users(phone,name) VALUES($1,$2) RETURNING id', [
          '+91933333000' + i,
          'Private ride test ' + i,
        ])
      ).rows[0];
      const role = i < 2 ? 'PASSENGER' : 'DRIVER';
      await pool.query('INSERT INTO user_roles(user_id,role) VALUES($1,$2)', [u.id, role]);
      actors.push({ id: u.id, roles: [role] });
      if (role === 'DRIVER')
        await pool.query(
          'INSERT INTO driver_profiles(user_id,verification,online) VALUES($1,$2,true)',
          [u.id, i === 4 ? 'PENDING' : 'APPROVED'],
        );
    }
    const [p, other, d1, d2, pending] = actors;
    const vehicles = [];
    for (const [i, d] of [d1, d2, pending].entries())
      vehicles.push(
        (
          await pool.query(
            "INSERT INTO vehicles(driver_id,registration,category,capacity,approved) VALUES($1,$2,'AUTO',3,true) RETURNING id",
            [d.id, 'TEST-PRIVATE-' + i],
          )
        ).rows[0].id,
      );
    const location = {
      lat: 10.06,
      lng: 76.63,
      accuracyM: 10,
      recordedAt: new Date().toISOString(),
    };
    await assert.rejects(rides.location(p, location));
    await assert.rejects(rides.location(pending, location));
    await rides.location(d1, location);
    await rides.location(d2, location);
    const input = {
      pickup: { lat: 10.06, lng: 76.63 },
      dropoff: { lat: 10.08, lng: 76.64 },
      category: 'AUTO',
      pickupLabel: 'Test pickup',
      dropoffLabel: 'Test destination',
    };
    const originalBeta = process.env.BETA_AUTH_ENABLED;
    process.env.BETA_AUTH_ENABLED = 'false';
    await assert.rejects(rides.quote({ ...input, category: 'TAXI' }));
    process.env.BETA_AUTH_ENABLED = 'true';
    const betaQuote = await rides.quote({ ...input, category: 'TAXI' });
    assert.equal(betaQuote.betaPrice, true);
    if (originalBeta === undefined) delete process.env.BETA_AUTH_ENABLED;
    else process.env.BETA_AUTH_ENABLED = originalBeta;
    const q = await rides.quote(input);
    assert.ok(q.farePaise > 0);
    assert.equal(q.distanceSource, 'STRAIGHT_LINE');
    await assert.rejects(rides.quote({ ...input, dropoff: input.pickup }));
    await assert.rejects(
      bookings.privateCreate(
        p,
        { ...input, expectedFarePaise: q.farePaise + 1 },
        'wrong-fare-test',
      ),
    );
    const b = await bookings.privateCreate(
      p,
      { ...input, expectedFarePaise: q.farePaise },
      'private-test-request',
    );
    assert.equal(
      (
        await bookings.privateCreate(
          p,
          { ...input, expectedFarePaise: q.farePaise },
          'private-test-request',
        )
      ).id,
      b.id,
    );
    await assert.rejects(bookings.privateCreate(p, input, 'duplicate-active-test'));
    assert.equal(
      (await rides.offers(d1)).some((o) => o.id === b.id),
      true,
    );
    assert.equal((await rides.offers(pending)).length, 0);
    await assert.rejects(rides.detail(other, b.id));
    await assert.rejects(rides.detail(d1, b.id));
    await assert.rejects(bookings.privateAccept(d1, b.id, vehicles[1]));
    const accepted = await Promise.allSettled([
      bookings.privateAccept(d1, b.id, vehicles[0]),
      bookings.privateAccept(d2, b.id, vehicles[1]),
    ]);
    assert.equal(accepted.filter((a) => a.status === 'fulfilled').length, 1);
    const winner = accepted[0].status === 'fulfilled' ? d1 : d2;
    const detail = await rides.detail(p, b.id);
    assert.equal(detail.pickup_lat, 10.06);
    assert.equal(detail.pickup_label, 'Test pickup');
    assert.equal(detail.driver_lat, 10.06);
    const second = await bookings.privateCreate(other, input, 'second-passenger-test');
    await assert.rejects(
      bookings.privateAccept(winner, second.id, winner === d1 ? vehicles[0] : vehicles[1]),
    );
    let current = await bookings.privateStatus(winner, b.id, 'ARRIVED', detail.version);
    await assert.rejects(bookings.privateStatus(winner, b.id, 'IN_PROGRESS', current.version));
    await assert.rejects(rides.confirmPickup(other, b.id, current.version));
    await assert.rejects(rides.confirmPickup(winner, b.id, current.version));
    current = await rides.confirmPickup(p, b.id, current.version);
    current = await bookings.privateStatus(winner, b.id, 'IN_PROGRESS', current.version);
    await assert.rejects(bookings.privateStatus(p, b.id, 'COMPLETED', current.version));
    current = await bookings.privateStatus(winner, b.id, 'COMPLETED', current.version);
    assert.equal((await rides.detail(p, b.id)).driver_lat, null);
    const paid = await bookings.cash(winner, b.id, 'private-cash-test');
    assert.equal((await bookings.cash(winner, b.id, 'private-cash-test')).id, paid.id);
    assert.equal((await rides.detail(p, b.id)).cash_recorded, true);
    await rides.reject(winner, second.id);
    assert.equal(
      (await rides.offers(winner)).some((o) => o.id === second.id),
      false,
    );
    await assert.rejects(
      bookings.privateAccept(winner, second.id, winner === d1 ? vehicles[0] : vehicles[1]),
    );
    const otherDriver = winner === d1 ? d2 : d1;
    await pool.query(
      "UPDATE driver_locations SET recorded_at=now()-interval '2 minutes' WHERE user_id=$1",
      [otherDriver.id],
    );
    assert.equal(
      (await rides.offers(otherDriver)).some((o) => o.id === second.id),
      false,
    );
    await assert.rejects(
      bookings.privateAccept(
        otherDriver,
        second.id,
        otherDriver === d1 ? vehicles[0] : vehicles[1],
      ),
    );
    await pool.query(
      "UPDATE private_bookings SET created_at=now()-interval '4 minutes' WHERE id=$1",
      [second.id],
    );
    assert.equal((await rides.detail(other, second.id)).status, 'CANCELLED');
    assert.equal((await rides.list(p, 'driver')).length, 0);
    assert.equal(
      (await rides.list(p, 'passenger')).some((x) => x.id === b.id),
      true,
    );
  },
);
