#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/Forest.app"
INSTALL_DIR="$HOME/Applications"
TARGET_APP="$INSTALL_DIR/Forest.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$ROOT_DIR/scripts/build_app.sh" >/dev/null
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"

SIGN_IDENTITY="${LOCALVOICEINPUT_CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  xcrun codesign --force --sign "$SIGN_IDENTITY" "$TARGET_APP" >/dev/null
else
  xcrun codesign --force --sign - "$TARGET_APP" >/dev/null
fi

echo "$TARGET_APP"
