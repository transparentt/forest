#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.localvoiceinput/bin"
PYTHON="$HOME/.localvoiceinput/venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
  echo "Missing runner Python: $PYTHON" >&2
  echo "Create it with: scripts/setup_runner_env.sh" >&2
  exit 2
fi

mkdir -p "$INSTALL_DIR"
rm -f "$INSTALL_DIR/gemma_customization_server.py"
{
  printf '#!%s\n' "$PYTHON"
  tail -n +2 "$ROOT_DIR/scripts/qwen3_asr_transcribe.py"
} > "$INSTALL_DIR/qwen3_asr_transcribe.py"
chmod +x "$INSTALL_DIR/qwen3_asr_transcribe.py"

{
  printf '#!%s\n' "$PYTHON"
  tail -n +2 "$ROOT_DIR/scripts/qwen3_asr_server.py"
} > "$INSTALL_DIR/qwen3_asr_server.py"
chmod +x "$INSTALL_DIR/qwen3_asr_server.py"

echo "$INSTALL_DIR/qwen3_asr_transcribe.py"
