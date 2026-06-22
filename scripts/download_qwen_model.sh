#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${LOCALVOICEINPUT_QWEN_MODEL:-$HOME/.localvoiceinput/models/Qwen3-ASR-1.7B}"

cd "$ROOT_DIR"

if [[ ! -x "$ROOT_DIR/.venv/bin/hf" ]]; then
  echo "Missing hf CLI. Run scripts/setup_runner_env.sh first." >&2
  exit 2
fi

mkdir -p "$MODEL_DIR"
"$ROOT_DIR/.venv/bin/hf" download Qwen/Qwen3-ASR-1.7B --local-dir "$MODEL_DIR"

echo "$MODEL_DIR"
