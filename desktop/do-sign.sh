#!/bin/bash
set -e
cd "$(dirname "$0")"
export TAURI_SIGNING_PRIVATE_KEY
TAURI_SIGNING_PRIVATE_KEY=$(cat src-tauri/tauri.key)
echo "Key length: ${#TAURI_SIGNING_PRIVATE_KEY}"
bunx @tauri-apps/cli signer sign "src-tauri/target/release/bundle/nsis/Claude Code 咪咪_0.2.1_x64-setup.exe"
