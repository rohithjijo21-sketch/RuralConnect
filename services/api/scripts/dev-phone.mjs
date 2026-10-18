import { PGlite } from '@electric-sql/pglite';
import { postgis } from '@electric-sql/pglite-postgis';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { PGLiteSocketServer } from '@electric-sql/pglite-socket';
import { spawn } from 'node:child_process';
import { randomBytes, randomInt } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import os from 'node:os';
if (process.env.NODE_ENV === 'production')
  throw Error('The phone-test server is development only.');
const repo = fileURLToPath(new URL('../../../', import.meta.url));
const local = path.join(repo, '.local-data');
await mkdir(local, { recursive: true });
const configPath = path.join(local, 'phone-config.json');
let config;
try {
  config = JSON.parse(await readFile(configPath, 'utf8'));
} catch {
  config = {
    sandboxKey: 'RC-' + randomBytes(12).toString('hex'),
    otp: String(randomInt(100000, 1000000)),
  };
  await writeFile(configPath, JSON.stringify(config, null, 2));
}
const db = await PGlite.create({
  dataDir: path.join(local, 'phone-postgres'),
  extensions: { postgis, pgcrypto },
});
const socket = new PGLiteSocketServer({ db, host: '127.0.0.1', port: 55434, maxConnections: 20 });
await socket.start();
const env = {
  ...process.env,
  NODE_ENV: 'development',
  OTP_MODE: 'sandbox',
  DATABASE_URL: 'postgres://postgres:postgres@127.0.0.1:55434/ruralconnect_phone_test',
  PORT: process.env.PORT ?? '3001',
  SANDBOX_ACCESS_KEY: config.sandboxKey,
  SANDBOX_OTP_CODE: config.otp,
  RURALCONNECT_TEST_IMPORT: '',
};
const cwd = fileURLToPath(new URL('..', import.meta.url));
async function run(file) {
  const c = spawn(process.execPath, ['--import', 'tsx', file], { cwd, env, stdio: 'inherit' });
  c.on('error', (e) => {
    throw e;
  });
  const code = await new Promise((resolve) => c.on('exit', resolve));
  if (code !== 0) throw Error(file + ' failed');
}
try {
  await run('scripts/migrate.ts');
  await run('scripts/seed.ts');
} catch (e) {
  await socket.stop();
  await db.close();
  throw e;
}
const addresses = Object.entries(os.networkInterfaces()).flatMap(([name, list]) =>
  (list ?? [])
    .filter(
      (a) =>
        a.family === 'IPv4' &&
        !a.internal &&
        /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)/.test(a.address),
    )
    .map((a) => ({ name, url: 'http://' + a.address + ':' + env.PORT + '/v1' })),
);
const notes = [
  '# RuralConnect phone testing — private local setup',
  '',
  'Keep this computer and your Android phone on the same Wi-Fi. Keep this server running. These are test fixtures, not production accounts.',
  '',
  '## Server addresses',
  '',
  ...addresses.map((a) => '- ' + a.name + ': ' + a.url),
  '',
  'Enter one address in the app’s Server address field, then tap Connect and continue. If it fails, check Wi-Fi isolation and allow Node/RuralConnect TCP ' +
    env.PORT +
    ' on the Windows private network only. Do not expose this test server publicly.',
  '',
  '## Local test sign-in',
  '',
  'Sandbox access key: ' + config.sandboxKey,
  '',
  'Six-digit OTP: ' + config.otp,
  '',
  'No SMS is sent. Passenger: +919000000001. Driver: +919000000002. Bus crew: +919000000003. Operator portal: +919000000004.',
  '',
  'The passenger UI demo is read-only and requires no server. For real test bookings or bus updates, connect all three apps to the SAME server. Approved driver/vehicle fixtures are DEMO data. Publish a shared service in Driver, reserve in Passenger, and observe the backend-confirmed reservation in Driver. Bus crew can select today’s assigned service, mark boarding/running, then enable actual foreground GPS while safely stopped.',
  '',
  'The embedded PostgreSQL/PostGIS runtime is experimental and local-test-only. Data persists in the ignored .local-data folder. Commercial deployment requires a supported native PostgreSQL environment and the outstanding release gates.',
  '',
  'Start again with pnpm dev:phone from the repository root. Stop with Ctrl+C.',
].join('\n');
const notesPath = process.env.PHONE_TEST_NOTES ?? path.resolve(repo, '..', 'PHONE_TESTING.md');
await writeFile(notesPath, notes + '\n');
console.log('\nPHONE TEST SERVER — private development only');
for (const a of addresses) console.log(a.name + ': ' + a.url);
console.log('Private test sign-in details saved to ' + notesPath);
const app = spawn(process.execPath, ['--import', 'tsx', 'src/main.ts'], {
  cwd,
  env,
  stdio: 'inherit',
});
let closing = false;
async function stop() {
  if (closing) return;
  closing = true;
  app.kill('SIGTERM');
  await new Promise((resolve) => setTimeout(resolve, 250));
  await socket.stop();
  await db.close();
}
process.on('SIGINT', () => void stop());
process.on('SIGTERM', () => void stop());
app.on('exit', async (code) => {
  await stop();
  process.exitCode = code ?? 0;
});
