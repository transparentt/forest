#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="local.localvoiceinput.app"

tccutil reset Accessibility "$BUNDLE_ID" || true
tccutil reset ListenEvent "$BUNDLE_ID" || true

echo "Reset Accessibility and Input Monitoring permissions for $BUNDLE_ID."
echo "Open System Settings > Privacy & Security, then add ~/Applications/Forest.app again."
