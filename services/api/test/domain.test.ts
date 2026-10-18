import test from 'node:test';
import assert from 'node:assert/strict';
import {
  canTransition,
  fresh,
  plausible,
  safeFare,
  hash,
  token,
  busStates,
} from '../src/domain.js';
test('bus lifecycle permits intended path', () => {
  assert.ok(canTransition('SCHEDULED', 'BOARDING', false));
  assert.ok(canTransition('BOARDING', 'RUNNING', false));
  assert.ok(canTransition('RUNNING', 'COMPLETED', false));
});
test('completed services cannot be restarted by any actor', () => {
  for (const state of busStates) assert.equal(canTransition('COMPLETED', state, true), false);
});
test('reinstatement requires operator and only returns to scheduled', () => {
  assert.equal(canTransition('CANCELLED', 'SCHEDULED', false), false);
  assert.equal(canTransition('CANCELLED', 'SCHEDULED', true), true);
  assert.equal(canTransition('CANCELLED', 'RUNNING', true), false);
});
test('invalid jumps and self transitions are rejected', () => {
  assert.equal(canTransition('SCHEDULED', 'COMPLETED', true), false);
  for (const state of busStates) assert.equal(canTransition(state, state, true), false);
});
test('GPS freshness distinguishes absent, stale, future and current data', () => {
  const now = Date.now();
  assert.equal(fresh(null, now), false);
  assert.equal(fresh(new Date(now - 61000), now), false);
  assert.equal(fresh(new Date(now + 11000), now), false);
  assert.equal(fresh(new Date(now - 30000), now), true);
});
test('GPS rejects teleportation and out-of-order updates', () => {
  const now = Date.now(),
    old = { lat: 10, lng: 76, at: new Date(now - 1000) };
  assert.equal(plausible(old, { lat: 20, lng: 80, at: new Date(now) }, now), false);
  assert.equal(plausible(old, old, now), false);
  assert.equal(plausible(old, { lat: 10.00001, lng: 76, at: new Date(now) }, now), true);
});
test('GPS rejects expired, future and invalid coordinates', () => {
  const now = Date.now();
  for (const n of [
    { lat: 91, lng: 76, at: new Date(now) },
    { lat: 10, lng: 181, at: new Date(now) },
    { lat: 10, lng: 76, at: new Date(now - 121000) },
    { lat: 10, lng: 76, at: new Date(now + 11000) },
  ])
    assert.equal(plausible(null, n, now), false);
});
test('fares remain integer minor units', () => {
  assert.equal(safeFare(3, 1250), 3750);
  assert.throws(() => safeFare(2, 1.1));
  assert.throws(() => safeFare(-1, 10));
  assert.throws(() => safeFare(2, Number.MAX_SAFE_INTEGER));
});
test('session tokens are high entropy and persisted only as hashes', () => {
  const a = token(),
    b = token();
  assert.notEqual(a, b);
  assert.ok(a.length >= 40);
  assert.equal(hash(a).length, 64);
  assert.notEqual(hash(a), a);
});
