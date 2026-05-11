#!/bin/bash
cd "$(dirname "$0")"
unset TAURI_SIGNING_PRIVATE_KEY
unset TAURI_SIGNING_PRIVATE_KEY_PATH
bun run tauri build
