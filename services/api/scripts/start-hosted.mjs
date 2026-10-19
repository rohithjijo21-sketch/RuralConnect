import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { runtimeConfig } from '../dist/config.js';

// Fail before touching the database if hosted configuration is incomplete.
runtimeConfig();
if (process.env.NODE_ENV !== 'production') {
  throw new Error('Hosted startup requires NODE_ENV=production');
}

// Free hosting has no pre-deploy job/shell. Existing migrations use a
// transaction and advisory lock, so restarts serialize and skip applied files.
const migration = spawnSync(process.execPath, ['--import', 'tsx', 'scripts/migrate.ts'], {
  cwd: fileURLToPath(new URL('../', import.meta.url)),
  env: process.env,
  stdio: ['ignore', 'inherit', 'pipe'],
});
if (migration.error || migration.status !== 0) {
  // Do not forward raw database errors that can contain connection details.
  console.error('Database migration failed; API startup stopped. Check database configuration and migrations.');
  process.exit(1);
}

await import('../dist/main.js');
