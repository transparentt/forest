#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/Forest.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BINARY_DIR="$ROOT_DIR/.build/bin"
SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

cd "$ROOT_DIR"
mkdir -p "$BINARY_DIR" "$CLANG_MODULE_CACHE_PATH"

xcrun swiftc \
  -sdk "$SDKROOT" \
  -target arm64-apple-macosx15.0 \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/LocalVoiceInput/*.swift \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework AVFoundation \
  -framework Carbon \
  -o "$BINARY_DIR/Forest"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_DIR/Forest" "$MACOS_DIR/Forest"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -f "Resources/AppIcon.icns" ]]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

SIGN_IDENTITY="${LOCALVOICEINPUT_CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development|Developer ID Application|Mac Developer/ { print $2; exit }')"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  xcrun codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
else
  xcrun codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "$APP_DIR"
