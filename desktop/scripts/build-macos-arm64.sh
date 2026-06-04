#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${DESKTOP_DIR}/.." && pwd)"

TARGET_TRIPLE="aarch64-apple-darwin"
CANONICAL_OUTPUT_DIR="${DESKTOP_DIR}/build-artifacts/macos-arm64"
APP_BUNDLE_NAME="Claude Code 咪咪.app"
APP_BUNDLE_ID="com.claude-code-haha.desktop"

usage() {
  cat <<'EOF'
Build Claude Code 咪咪 desktop for macOS Apple Silicon and output a DMG.

Usage:
  ./desktop/scripts/build-macos-arm64.sh [extra electron-builder args...]

Environment:
  SKIP_INSTALL=1   Skip `bun install` in the repo root and desktop app.
  SIGN_BUILD=1     Allow electron-builder to auto-discover signing identities.
  REBUILD_NATIVE=1 Run `electron-builder install-app-deps` before packaging.
  MAC_TARGETS      Electron Builder macOS targets. Defaults to "dmg zip".
  SKIP_PACKAGE_SMOKE=1
                   Skip package-smoke verification after copying artifacts.
  REQUIRE_MACOS_GATEKEEPER_SMOKE=1
                   Require Gatekeeper approval during post-build package-smoke.
  OPEN_OUTPUT=1    Open the canonical artifact output directory in Finder after a successful build.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[build-macos-arm64] This script must run on macOS." >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "[build-macos-arm64] This script is intended for Apple Silicon hosts (arm64)." >&2
  exit 1
fi

for command in bun codesign hdiutil; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "[build-macos-arm64] Missing required command: ${command}" >&2
    exit 1
  fi
done

read -r -a MAC_TARGET_ARRAY <<< "${MAC_TARGETS:-dmg zip}"
if [[ "${#MAC_TARGET_ARRAY[@]}" -eq 0 ]]; then
  echo "[build-macos-arm64] MAC_TARGETS must contain at least one electron-builder macOS target." >&2
  exit 1
fi

has_mac_target() {
  local target="$1"
  for candidate in "${MAC_TARGET_ARRAY[@]}"; do
    if [[ "${candidate}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

if has_mac_target "dmg"; then
  STALE_DMG_MOUNTS="$(hdiutil info | grep -F "${ELECTRON_OUTPUT_DIR}/.temp" || true)"
  if [[ -n "${STALE_DMG_MOUNTS}" ]]; then
    echo "[build-macos-arm64] Found stale Electron Builder temporary DMG mounts in this worktree:" >&2
    echo "${STALE_DMG_MOUNTS}" >&2
    echo "[build-macos-arm64] Detach the stale disk image or restart DiskImages before building the dmg target." >&2
    echo "[build-macos-arm64] To verify the update zip path without DMG, rerun with MAC_TARGETS=zip." >&2
    exit 1
  fi
fi

if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
  echo "[build-macos-arm64] Installing root dependencies..."
  (cd "${REPO_ROOT}" && bun install)

  echo "[build-macos-arm64] Installing desktop dependencies..."
  (cd "${DESKTOP_DIR}" && bun install)
fi

echo "[build-macos-arm64] Cleaning stale Electron outputs..."
rm -rf "${DESKTOP_DIR}/dist"
rm -rf "${DESKTOP_DIR}/electron-dist"
rm -rf "${ELECTRON_OUTPUT_DIR}"
rm -rf "${CANONICAL_OUTPUT_DIR}"
rm -f "${DESKTOP_DIR}/tsconfig.tsbuildinfo"
rm -rf "${DESKTOP_DIR}/src-tauri/binaries/claude-sidecar-"*

echo "[build-macos-arm64] Building sidecars for ${TARGET_TRIPLE}..."
(cd "${DESKTOP_DIR}" && SIDECAR_TARGET_TRIPLE="${TARGET_TRIPLE}" bun run build:sidecars)

echo "[build-macos-arm64] Building renderer and Electron main/preload bundles..."
(cd "${DESKTOP_DIR}" && bun run build && bun run build:electron)

if [[ "${REBUILD_NATIVE:-0}" == "1" ]]; then
  echo "[build-macos-arm64] Rebuilding native dependencies for Electron ABI..."
  (cd "${DESKTOP_DIR}" && bunx electron-builder install-app-deps)
  (cd "${DESKTOP_DIR}" && bun run prepare:node-pty)
fi

echo "[build-macos-arm64] Cleaning empty dmg-builder cache directories..."
(cd "${DESKTOP_DIR}" && bash ./scripts/clean-dmg-builder-cache.sh)

BUILDER_ARGS=(bunx electron-builder --mac "${MAC_TARGET_ARRAY[@]}" --arm64 --publish never)
if [[ "${SIGN_BUILD:-0}" != "1" ]]; then
  export CSC_IDENTITY_AUTO_DISCOVERY=false
  # package.json sets mac.notarize=true for the signed CI release path. A local
  # unsigned build has no Developer ID credentials, so explicitly disable
  # notarization here to keep `electron:package` working without an Apple account.
  BUILDER_ARGS+=(-c.mac.notarize=false)
fi
if [[ "$#" -gt 0 ]]; then
  BUILDER_ARGS+=("$@")
fi

echo "[build-macos-arm64] Packaging Electron app..."
(cd "${DESKTOP_DIR}" && "${BUILDER_ARGS[@]}")

mkdir -p "${CANONICAL_OUTPUT_DIR}"
find "${CANONICAL_OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

find_latest_file() {
  local search_dir="$1"
  local pattern="$2"
  if [[ -d "${search_dir}" ]]; then
    find "${search_dir}" -maxdepth 1 -type f -name "${pattern}" | sort | tail -n 1
  fi
}

find_latest_dir() {
  local search_dir="$1"
  local pattern="$2"
  if [[ -d "${search_dir}" ]]; then
    find "${search_dir}" -maxdepth 1 -type d -name "${pattern}" | sort | tail -n 1
  fi
}

LATEST_DMG="$(find_latest_file "${TARGETED_DMG_DIR}" '*.dmg')"
if [[ -z "${LATEST_DMG}" ]]; then
  LATEST_DMG="$(find_latest_file "${FALLBACK_DMG_DIR}" '*.dmg')"
fi

LATEST_APP="$(find_latest_dir "${TARGETED_APP_DIR}" '*.app')"
if [[ -z "${LATEST_APP}" ]]; then
  LATEST_APP="$(find_latest_dir "${FALLBACK_APP_DIR}" '*.app')"
fi

build_canonical_dmg() {
  local app_bundle="$1"
  local dmg_output="$2"
  local staging_dir
  local rw_dmg

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/cc-haha-dmg.XXXXXX")"
  rw_dmg="$(mktemp "${TMPDIR:-/tmp}/cc-haha-rw.XXXXXX").dmg"

  cp -R "${app_bundle}" "${staging_dir}/"
  ln -s /Applications "${staging_dir}/Applications"

  # Create a read-write DMG first so we can customize the Finder layout
  hdiutil create \
    -volname "Claude Code 咪咪" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDRW \
    "${rw_dmg}" >/dev/null

  rm -rf "${staging_dir}"

  # Mount the read-write DMG and apply Finder layout via AppleScript
  local dev_name mount_dir
  dev_name=$(hdiutil attach -readwrite -noverify -noautoopen -nobrowse "${rw_dmg}" \
    | grep -E '^/dev/' | head -1 | awk '{print $1}')
  mount_dir=$(hdiutil info | grep -E "${dev_name}" | tail -1 | awk '{$1=$2=""; print}' | xargs)

  # Finder AppleScript 在新版 macOS (Sequoia+) 上某些属性
  # (toolbar/statusbar visible、某些 container window 属性) 不再支持,
  # 会返回 -10006 错误。美化失败不是 blocker —— 即便 layout 没设上,
  # DMG 本身还是可用的,只是用户打开时看到的是 Finder 默认排布。
  # 所以这里允许 osascript 非零退出,只 warn,不让 set -e 炸掉整个脚本。
  if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "Claude Code 咪咪"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 760, 500}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set position of item "${APP_BUNDLE_NAME}" of container window to {180, 170}
    set position of item "Applications" of container window to {480, 170}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
  then
    echo "[build-macos-arm64] WARN: Finder layout AppleScript failed (likely macOS version incompatible); DMG will use default Finder layout" >&2
  fi

  sync
  # osascript 可能已经让 Finder 打开了 volume 窗口,正常 detach 可能因为
  # "Resource busy" 失败。失败时用 -force 二次尝试。
  hdiutil detach "${dev_name}" -quiet 2>/dev/null \
    || hdiutil detach "${dev_name}" -force -quiet

  # Convert to compressed read-only DMG
  hdiutil convert "${rw_dmg}" -format UDZO -o "${dmg_output}" -ov >/dev/null
  rm -f "${rw_dmg}"
}

codesign_cdhash() {
  local executable="$1"
  codesign -d --verbose=4 "${executable}" 2>&1 \
    | awk -F= '/^CDHash=/{print $2; exit}'
}

sign_canonical_app_bundle() {
  local app_bundle="$1"
  local sidecar="${app_bundle}/Contents/MacOS/claude-sidecar"
  local sidecar_cdhash_before=""
  local sidecar_cdhash_after=""

  if [[ -x "${sidecar}" ]]; then
    sidecar_cdhash_before="$(codesign_cdhash "${sidecar}")"
  fi

  # Tauri --no-sign leaves the outer .app with no sealed resources, which
  # fails strict bundle validation once Resources/icon.icns exists. Sign only
  # the outer bundle: do not pass --deep, because re-signing claude-sidecar
  # changes its code-signature hash and breaks existing macOS Keychain ACLs.
  codesign --force --sign - --timestamp=none "${app_bundle}"

  if [[ -x "${sidecar}" ]]; then
    sidecar_cdhash_after="$(codesign_cdhash "${sidecar}")"
    if [[ "${sidecar_cdhash_before}" != "${sidecar_cdhash_after}" ]]; then
      echo "[build-macos-arm64] ERROR: sidecar signature hash changed while signing app bundle" >&2
      echo "[build-macos-arm64] before=${sidecar_cdhash_before}" >&2
      echo "[build-macos-arm64] after=${sidecar_cdhash_after}" >&2
      exit 1
    fi
  fi

  codesign --verify --deep --strict --verbose=2 "${app_bundle}"
}

if [[ -n "${LATEST_APP}" ]]; then
  # Normalize the Tauri-produced app in place before copying it anywhere.
  # Without this, opening target/.../bundle/macos/Claude Code 咪咪.app directly
  # uses the executable's ad-hoc signing identifier instead of the app bundle id,
  # which makes macOS notification authorization behave like a different app.
  sign_canonical_app_bundle "${LATEST_APP}"

  # 不要 deep re-sign。曾经脚本在这里跑过
  # `codesign --force --deep --sign - --identifier <bundle-id>` 来统一
  # sidecar 和外层的 signing identifier,但这会改变 sidecar binary 的
  # code signature hash —— macOS Keychain ACL 按 hash 识别 caller,
  # 重签完再访问时会被 ACL 当作"陌生 binary"静默拒绝,导致 CLI 读不到
  # OAuth token,最终请求打到 Anthropic 返回 403 "Request not allowed"。
  # 这里只浅签外层 bundle,让 .app 拥有有效资源封印,同时保留 sidecar hash。
  cp -R "${LATEST_APP}" "${CANONICAL_OUTPUT_DIR}/"
  sign_canonical_app_bundle "${CANONICAL_OUTPUT_DIR}/${APP_BUNDLE_NAME}"
  rm -f "${CANONICAL_OUTPUT_DIR}/"*.dmg
  CANONICAL_DMG="${CANONICAL_OUTPUT_DIR}/$(basename "${LATEST_DMG:-Claude Code 咪咪_0.1.0_aarch64.dmg}")"
  build_canonical_dmg \
    "${CANONICAL_OUTPUT_DIR}/${APP_BUNDLE_NAME}" \
    "${CANONICAL_DMG}"

  if [[ -n "${LATEST_DMG}" ]]; then
    cp -f "${CANONICAL_DMG}" "${LATEST_DMG}"
  fi
elif [[ -n "${LATEST_DMG}" ]]; then
  cp -f "${LATEST_DMG}" "${CANONICAL_OUTPUT_DIR}/"
fi
find "${ELECTRON_OUTPUT_DIR}" -maxdepth 1 -type f \( -name '*.dmg' -o -name '*.zip' -o -name '*.blockmap' -o -name 'latest-mac.yml' \) -exec cp -f {} "${CANONICAL_OUTPUT_DIR}/" \;

cat > "${CANONICAL_OUTPUT_DIR}/BUILD_INFO.txt" <<EOF
Target triple: ${TARGET_TRIPLE}
Builder output: ${ELECTRON_OUTPUT_DIR}
Canonical output: ${CANONICAL_OUTPUT_DIR}
Built at: $(date '+%Y-%m-%d %H:%M:%S %z')
EOF

if [[ "${SKIP_PACKAGE_SMOKE:-0}" != "1" ]]; then
  PACKAGE_SMOKE_ARGS=(bun run test:package-smoke --platform macos --package-kind release --artifacts-dir desktop/build-artifacts/macos-arm64)
  if [[ "${REQUIRE_MACOS_GATEKEEPER_SMOKE:-0}" == "1" ]]; then
    PACKAGE_SMOKE_ARGS+=(--require-macos-gatekeeper)
  fi
  echo "[build-macos-arm64] Running package smoke..."
  (cd "${REPO_ROOT}" && "${PACKAGE_SMOKE_ARGS[@]}")
fi

echo
echo "[build-macos-arm64] Build finished."
echo "[build-macos-arm64] Canonical output: ${CANONICAL_OUTPUT_DIR}"

if [[ "${OPEN_OUTPUT:-0}" == "1" ]]; then
  open "${CANONICAL_OUTPUT_DIR}"
fi
