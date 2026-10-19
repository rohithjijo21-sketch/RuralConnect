import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, readdir, unlink, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';

test(
  'Invite beta: owner provisioning, single-use race, expiry, suspension, privileged-role denial and revocation',
  { skip: process.env.RUN_DB_TESTS !== '1' },
  async () => {
    process.env.RURALCONNECT_TEST_IMPORT = '1';
    process.env.BETA_AUTH_ENABLED = 'true';
    process.env.OTP_MODE = 'disabled';
    const { bootstrap } = await import('../../src/main.js');
    const { pool } = await import('../../src/db.js');
    const { hash, token } = await import('../../src/domain.js');
    const folder = await mkdtemp(join(tmpdir(), 'rc-beta-test-'));
    const app = await bootstrap(0);
    const base = 'http://127.0.0.1:' + app.getHttpServer().address().port + '/v1';
    let counter = 0;
    async function issue(phone: string, role: string) {
      const file = join(folder, 'invite-' + counter++);
      const child = spawn(
        process.execPath,
        ['--import', 'tsx', 'scripts/beta-invite.ts', phone, role, file],
        { cwd: new URL('../..', import.meta.url), env: process.env, stdio: 'ignore' },
      );
      const code = await new Promise((resolve) => {
        child.on('error', () => resolve(-1));
        child.on('exit', resolve);
      });
      assert.equal(code, 0);
      const text = await readFile(file, 'utf8');
      return text.match(/One-time invitation code: ([A-Za-z0-9_-]{43})/)![1];
    }
    async function redeem(phone: string, inviteCode: string, extra = {}) {
      const r = await fetch(base + '/auth/beta/redeem', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone, inviteCode, consentVersion: 'test-beta-v1', ...extra }),
      });
      return { status: r.status, data: (await r.json()) as any };
    }
    try {
      const phone = '+919000000011';
      const invite = await issue(phone, 'PASSENGER');
      assert.equal((await redeem('+919000000012', invite)).status, 401);
      assert.equal((await redeem(phone, invite, { role: 'ADMIN' })).status, 400);
      const results = await Promise.all([redeem(phone, invite), redeem(phone, invite)]);
      assert.deepEqual(results.map((x) => x.status).sort(), [201, 401]);
      const session = results.find((x) => x.status === 201)!.data;
      const me = await fetch(base + '/me', {
        headers: { Authorization: 'Bearer ' + session.accessToken },
      });
      const profile = (await me.json()) as any;
      assert.deepEqual(profile.roles, ['PASSENGER']);
      const stored = (await pool.query('SELECT * FROM beta_invites WHERE user_id=$1', [profile.id]))
        .rows[0];
      assert.equal(stored.token_hash, hash(invite));
      assert.notEqual(stored.token_hash, invite);
      assert.ok(stored.consumed_at);
      const expired = await issue(phone, 'PASSENGER');
      await pool.query(
        "UPDATE beta_invites SET expires_at=now()-interval '1 second' WHERE token_hash=$1",
        [hash(expired)],
      );
      assert.equal((await redeem(phone, expired)).status, 401);
      const replaced = await issue(phone, 'PASSENGER'),
        replacement = await issue(phone, 'PASSENGER');
      assert.equal((await redeem(phone, replaced)).status, 401);
      assert.equal((await redeem(phone, replacement)).status, 201);
      const driverPhone = '+919000000012',
        driverInvite = await issue(driverPhone, 'DRIVER');
      const driver = await redeem(driverPhone, driverInvite);
      assert.equal(driver.status, 201);
      assert.equal(
        (
          await fetch(base + '/driver/availability', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              Authorization: 'Bearer ' + driver.data.accessToken,
            },
            body: JSON.stringify({ online: true }),
          })
        ).status,
        403,
      );
      const crewPhone = '+919000000013',
        crewInvite = await issue(crewPhone, 'BUS_CREW');
      await pool.query('UPDATE users SET suspended=true WHERE phone=$1', [crewPhone]);
      assert.equal((await redeem(crewPhone, crewInvite)).status, 401);
      const privileged = token();
      const admin = (
        await pool.query("INSERT INTO users(phone) VALUES('+919000000014') RETURNING id")
      ).rows[0];
      await pool.query("INSERT INTO user_roles VALUES($1,'ADMIN')", [admin.id]);
      await pool.query(
        "INSERT INTO beta_invites(user_id,token_hash,expires_at) VALUES($1,$2,now()+interval '1 day')",
        [admin.id, hash(privileged)],
      );
      assert.equal((await redeem('+919000000014', privileged)).status, 401);
      const pending = await issue(phone, 'PASSENGER');
      const revoke = spawn(process.execPath, ['--import', 'tsx', 'scripts/beta-revoke.ts', phone], {
        cwd: new URL('../..', import.meta.url),
        env: process.env,
        stdio: 'ignore',
      });
      assert.equal(
        await new Promise((resolve) => {
          revoke.on('error', () => resolve(-1));
          revoke.on('exit', resolve);
        }),
        0,
      );
      assert.equal((await redeem(phone, pending)).status, 401);
      assert.equal(
        (await fetch(base + '/me', { headers: { Authorization: 'Bearer ' + session.accessToken } }))
          .status,
        401,
      );
      process.env.BETA_AUTH_ENABLED = 'false';
      assert.equal((await redeem(phone, token())).status, 403);
    } finally {
      await app.close();
      await pool.end();
      for (const name of await readdir(folder)) await unlink(join(folder, name));
      await rmdir(folder);
    }
  },
);
