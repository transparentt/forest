#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$HOME/.localvoiceinput/venv"

cd "$ROOT_DIR"
mkdir -p "$HOME/.localvoiceinput"
uv venv --python 3.12 "$VENV_DIR"
uv pip install --python "$VENV_DIR/bin/python" -r requirements-runner.txt

echo "$VENV_DIR/bin/python"
