#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BINARY_DIR="$ROOT_DIR/.build/tests"
RUNNER_PYTHON="$HOME/.localvoiceinput/venv/bin/python"
SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/module-cache}"

if [[ ! -x "$RUNNER_PYTHON" ]]; then
  RUNNER_PYTHON="$ROOT_DIR/.venv/bin/python"
fi

cd "$ROOT_DIR"
mkdir -p "$TEST_BINARY_DIR" "$CLANG_MODULE_CACHE_PATH"

xcrun swiftc \
  -sdk "$SDKROOT" \
  -target arm64-apple-macosx15.0 \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  Sources/LocalVoiceInput/AppConfig.swift \
  Sources/LocalVoiceInput/ProcessingLogStore.swift \
  Sources/LocalVoiceInput/PermissionSettingsPresentation.swift \
  Sources/LocalVoiceInput/TranscriptionEngine.swift \
  Sources/LocalVoiceInput/PermissionGuide.swift \
  Sources/LocalVoiceInput/PasteInjector.swift \
  Sources/LocalVoiceInput/TextCustomizer.swift \
  Tests/LocalVoiceInputTests/*.swift \
  -parse-as-library \
  -o "$TEST_BINARY_DIR/LocalVoiceInputTests"

"$TEST_BINARY_DIR/LocalVoiceInputTests"

"$RUNNER_PYTHON" -m py_compile \
  "$ROOT_DIR/scripts/qwen3_asr_transcribe.py" \
  "$ROOT_DIR/scripts/qwen3_asr_server.py"

"$RUNNER_PYTHON" -m unittest "$ROOT_DIR/Tests/LocalVoiceInputTests/test_qwen3_asr_server.py"
