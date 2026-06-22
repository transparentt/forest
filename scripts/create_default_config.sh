#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="$HOME/.localvoiceinput"
CONFIG_PATH="$CONFIG_DIR/config.json"
RUNNER_PATH="$CONFIG_DIR/bin/qwen3_asr_transcribe.py"
SERVER_RUNNER_PATH="$CONFIG_DIR/bin/qwen3_asr_server.py"

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_PATH" ]]; then
  echo "$CONFIG_PATH"
  exit 0
fi

cat > "$CONFIG_PATH" <<JSON
{
  "paste": {
    "restoreDelay": 0.5
  },
  "recording": {
    "minimumDuration": 0.35,
    "sampleRate": 16000
  },
  "transcription": {
    "runnerPath": "$RUNNER_PATH",
    "serverRunnerPath": "$SERVER_RUNNER_PATH",
    "serverURL": "http://127.0.0.1:8765",
    "timeout": 180
  },
  "hotkey": {
    "keyCode": 61,
    "displayName": "右Option"
  },
  "customization": {
    "enabled": false,
    "model": "gemma4:e4b",
    "serverURL": "http://127.0.0.1:8765",
    "backendURL": "http://127.0.0.1:11434/api/generate",
    "timeout": 45,
    "instruction": "",
    "selectedPresetID": null,
    "presets": [],
    "voiceInstructionEnabled": false,
    "voiceInstructionMode": "append"
  },
  "userDictionary": {
    "enabled": false,
    "entries": []
  },
  "logging": {
    "enabled": true
  }
}
JSON

echo "$CONFIG_PATH"
