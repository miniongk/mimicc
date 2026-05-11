import { readFileSync } from 'fs';
import { spawnSync } from 'child_process';
import { join } from 'path';

const keyPath = join(import.meta.dir, 'src-tauri', 'tauri.key');
const key = readFileSync(keyPath, 'utf-8').trim();
console.log('Key length:', key.length);

const result = spawnSync('bunx', ['@tauri-apps/cli', 'signer', 'sign', '/tmp/setup.exe'], {
  cwd: import.meta.dir,
  env: { ...process.env, TAURI_SIGNING_PRIVATE_KEY: key },
  stdio: 'inherit',
  timeout: 120000,
});

console.log('Exit code:', result.status);
if (result.error) console.log('Error:', result.error.message);
