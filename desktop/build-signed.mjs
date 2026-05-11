import { readFileSync } from 'fs';
import { execSync } from 'child_process';
import { join } from 'path';

const keyPath = join(import.meta.dirname, 'src-tauri', 'tauri.key');
const key = readFileSync(keyPath, 'utf-8').trim();
console.log('Key loaded, length:', key.length);

process.env.TAURI_SIGNING_PRIVATE_KEY = key;

execSync('bun run tauri build', {
  cwd: import.meta.dirname,
  stdio: 'inherit',
  env: process.env,
});
