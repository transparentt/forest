# Forest

Forest is a privacy-first macOS menu bar dictation app prototype.

The first workflow is intentionally narrow:

1. Hold the configured shortcut key to record.
2. Release the configured shortcut key to stop recording.
3. A local Qwen3-ASR-1.7B runner transcribes the audio.
4. The app pastes the recognized Japanese text into the currently focused text field.

Audio and transcription stay local. The app does not call a cloud transcription API. For lower latency, the app starts a local ASR server on `127.0.0.1:8765` and keeps Qwen3-ASR loaded in memory.

## Requirements

- macOS 14 or later.
- Xcode or Command Line Tools with a matching Swift compiler and macOS SDK.
- Homebrew packages: `uv` and `ollama`.
- Microphone permission.
- Accessibility and Input Monitoring permissions for global shortcut detection and automatic paste.
- Local model files downloaded on each Mac by the setup scripts.

Install the small command-line dependencies:

```sh
brew install uv ollama
```

## Build

Clone the repository:

```sh
git clone https://github.com/transparentt/forest.git
cd forest
```

Full local setup, including Python runner dependencies, Qwen3-ASR model download, local config, app build, and install to `~/Applications/Forest.app`:

```sh
scripts/setup_all.sh
```

Open the installed app:

```sh
open ~/Applications/Forest.app
```

Start Ollama before using Gemma customization:

```sh
ollama serve
```

If `ollama serve` says it is already running, that is fine. Forest's local server will run `ollama pull gemma4:e4b` automatically the first time customization needs Gemma. To download it manually:

```sh
ollama pull gemma4:e4b
```

On first launch, open **Forest 設定 > 権限設定** and allow:

- Microphone
- Accessibility
- Input Monitoring

## Update From Git

On each Mac, update the app from GitHub:

```sh
git pull --ff-only
scripts/build_app.sh
scripts/install_app.sh
open ~/Applications/Forest.app
```

Run `scripts/setup_all.sh` instead of the build/install pair when setting up a Mac for the first time, or after changing runner dependencies.

## Development Commands

Build a minimal menu bar `.app` bundle:

```sh
scripts/build_app.sh
```

Install the local runner script into the default config path:

```sh
scripts/install_runner.sh
```

Create the default local config:

```sh
scripts/create_default_config.sh
```

Or do both:

```sh
scripts/setup_local.sh
```

Full local setup, including Python runner dependencies, model download, local config, and app build:

```sh
scripts/setup_all.sh
```

Install and run it from `~/Applications` to avoid macOS asking for Documents folder access during normal use:

```sh
scripts/install_app.sh
open ~/Applications/Forest.app
```

If Accessibility or Input Monitoring looks allowed in System Settings but the app still reports it as not allowed, reset this app's TCC entries and add the installed app again:

```sh
scripts/reset_permissions.sh
open ~/Applications/Forest.app
```

During development, the raw executable can also be run directly:

```sh
.build/bin/Forest
```

The installed `.app` bundle is preferred for microphone permission because it includes `NSMicrophoneUsageDescription` in `Resources/Info.plist` and does not run from the Documents folder.

Run tests:

```sh
scripts/run_tests.sh
```

## Toolchain Setup

If native compilation fails before compiling project source with messages like "this SDK is not supported by the compiler", install or select a matching Apple toolchain.

Known working target for this project:

- macOS 26.2 or later with Xcode 26.5, or
- A matching Xcode/Command Line Tools pair for the installed macOS release.

Check the active developer directory:

```sh
xcode-select -p
```

If Xcode is installed, select it:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

If only Command Line Tools are installed and the SDK/compiler versions do not match, install the matching Command Line Tools update from Software Update.

For this project, Command Line Tools for Xcode 26.5 with Swift 6.3.2 is enough for local development:

```sh
swift --version
xcrun --show-sdk-path
```

If the update does not appear, reinstall Command Line Tools:

```sh
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

Xcode.app is useful for signing, debugging, and distribution, but the prototype build does not require it. To install Xcode later:

```sh
mas get 497799835
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## Configuration

Create `~/.localvoiceinput/config.json`.

The menu bar app can create this file from **Create Default Config**. Use `config.example.json` as the starting point:

```json
{
  "recording": {
    "minimumDuration": 0.35,
    "sampleRate": 16000
  },
  "transcription": {
    "runnerPath": "/Users/YOUR_USER/.localvoiceinput/bin/qwen3_asr_transcribe.py",
    "serverRunnerPath": "/Users/YOUR_USER/.localvoiceinput/bin/qwen3_asr_server.py",
    "serverURL": "http://127.0.0.1:8765",
    "timeout": 180
  },
  "paste": {
    "restoreDelay": 0.5
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
    "entries": [
      {
        "source": "くえん",
        "target": "Qwen"
      },
      {
        "source": "あくあぼいす",
        "target": "AquaVoice"
      }
    ]
  },
  "logging": {
    "enabled": true
  }
}
```

The app first tries the local server at `serverURL`; if that is unavailable, it falls back to `runnerPath`. The fallback runner accepts one argument, the WAV file path, and prints recognized text to stdout.

If both `customization.enabled` and `userDictionary.enabled` are off, Forest skips Gemma entirely. If either post-processing feature is enabled, Forest sends the transcription to the unified local server at `customization.serverURL` and makes a single Gemma request that combines the customization instruction and dictionary entries. The server delegates generation to the local Gemma-compatible backend at `customization.backendURL` and tries to fetch the configured model with `ollama pull` if it is missing. On customization failure or timeout, Forest falls back to the original transcription text.

Example contract:

```sh
scripts/qwen3_asr_transcribe.py /tmp/localvoiceinput-example.wav
```

stdout:

```text
今日は会議の議事録を整理します。
```

## Privacy Notes

- Temporary WAV files are written to the system temporary directory.
- Temporary audio files are deleted after transcription or failure cleanup.
- When logging is enabled, recent ASR output, Gemma input, final output, and processing times are written to `~/.localvoiceinput/processing-log.jsonl`.
- Turn logging off in **Forest 設定 > ログ** if you do not want text logs saved locally.
- The default transcription path is a local executable, not a network service.

## Current Prototype Boundary

The app code defines the local Qwen runner contract, but does not bundle Qwen3-ASR-1.7B. This keeps the Git repository lightweight. Download the model locally on each Mac with `scripts/setup_all.sh` or `scripts/download_qwen_model.sh`.

The included `scripts/qwen3_asr_transcribe.py` runner expects a local model directory at:

```text
~/.localvoiceinput/models/Qwen3-ASR-1.7B
```

or a custom local path via:

```sh
export LOCALVOICEINPUT_QWEN_MODEL=/path/to/local/Qwen3-ASR-1.7B
```

It uses `local_files_only=True` when loading the model, so transcription does not trigger model downloads or external network access.

For manual server testing:

```sh
~/.localvoiceinput/bin/qwen3_asr_server.py
```

Then in another terminal:

```sh
curl -X POST --data-binary @/path/to/audio.wav "http://127.0.0.1:8765/transcribe?language=Japanese"
```

Runner Python dependencies are listed in `requirements-runner.txt`. Use a Python version supported by PyTorch, preferably Python 3.11 or 3.12:

```sh
scripts/setup_runner_env.sh
scripts/download_qwen_model.sh
```
