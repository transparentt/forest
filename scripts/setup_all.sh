#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/setup_runner_env.sh" >/dev/null
"$ROOT_DIR/scripts/download_qwen_model.sh" >/dev/null
"$ROOT_DIR/scripts/setup_local.sh"
"$ROOT_DIR/scripts/build_app.sh"
"$ROOT_DIR/scripts/install_app.sh"
