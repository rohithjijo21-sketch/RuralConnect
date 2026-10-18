import { createRequire } from 'node:module';
import { spawnSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const result = spawnSync(process.execPath, [require.resolve('next/dist/bin/next'), 'build'], {
  stdio: 'inherit',
  env: { ...process.env, RC_STATIC_EXPORT: '1' },
});
if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
