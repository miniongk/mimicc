#!/bin/bash
cd "$(dirname "$0")"
export TAURI_SIGNING_PRIVATE_KEY=$(cat src-tauri/tauri.key)
bun run tauri build
