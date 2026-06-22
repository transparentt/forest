#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/Forest-transfer.zip}"
OUTPUT_NAME="$(basename "$OUTPUT_PATH")"

cd "$ROOT_DIR"
rm -f "$OUTPUT_PATH"

zip -r "$OUTPUT_PATH" . \
  -x ".git/*" \
  -x ".build/*" \
  -x ".venv/*" \
  -x "**/__pycache__/*" \
  -x "*.pyc" \
  -x ".DS_Store" \
  -x "$OUTPUT_NAME"

echo "$OUTPUT_PATH"
