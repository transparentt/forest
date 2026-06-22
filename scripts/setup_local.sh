#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/install_runner.sh" >/dev/null
"$ROOT_DIR/scripts/create_default_config.sh"
