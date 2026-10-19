import { PGlite } from '@electric-sql/pglite';
import { postgis } from '@electric-sql/pglite-postgis';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { spawn } from 'node:child_process';
import { readFile, readdir } from 'node:fs/promises';
const db = await PGlite.create({ extensions: { postgis, pgcrypto } });
for (const name of (await readdir(new URL('../migrations/', import.meta.url))).sort())
  await db.exec(await readFile(new URL('../migrations/' + name, import.meta.url), 'utf8'));
await db.exec(
  "CREATE TABLE schema_migrations(name text PRIMARY KEY); INSERT INTO schema_migrations VALUES ('001_foundation.sql'),('002_bookings.sql'),('003_beta_invites.sql');",
);
console.log('All migrations applied to embedded PostgreSQL/PostGIS');
const server = new PGLiteSocketServer({ db, host: '127.0.0.1', port: 55432, maxConnections: 20 });
await server.start();
const env = {
  ...process.env,
  DATABASE_URL: 'postgres://postgres:postgres@127.0.0.1:55432/ruralconnect_test',
  RUN_DB_TESTS: '1',
  NODE_ENV: 'test',
};
try {
  const seed = spawn(process.execPath, ['--import', 'tsx', 'scripts/seed.ts'], {
    env: { ...env, OTP_MODE: 'sandbox' },
    stdio: 'inherit',
    cwd: new URL('..', import.meta.url),
  });
  if ((await new Promise((resolve) => seed.on('exit', resolve))) !== 0) throw Error('Seed failed');
  const child = spawn(
    process.execPath,
    [
      '--import',
      'tsx',
      '--test',
      '--test-concurrency=1',
      'test/integration/bus.test.ts',
      'test/integration/http.test.ts',
      'test/integration/beta.test.ts',
    ],
    { env, stdio: 'inherit', cwd: new URL('..', import.meta.url) },
  );
  const code = await new Promise((resolve) => child.on('exit', resolve));
  process.exitCode = code;
} finally {
  await server.stop();
  await db.close();
}
