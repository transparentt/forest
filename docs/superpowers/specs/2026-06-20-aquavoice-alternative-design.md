# AquaVoice Alternative Design

Date: 2026-06-20

## Goal

Build a privacy-first macOS native dictation app that can replace AquaVoice for Japanese voice input.

The first version should do one workflow well:

1. The user holds the right Option key.
2. Recording starts immediately.
3. The user speaks Japanese.
4. The user releases the right Option key.
5. Recording stops.
6. A local Qwen ASR model transcribes the speech.
7. The recognized text is inserted into the currently focused text field automatically.

The app must run fully locally. Audio and transcription content must not be sent to any external service.

## Core Decisions

- App type: macOS native menu bar app.
- Main app implementation: Swift and SwiftUI.
- Recognition model: Qwen3-ASR-1.7B, chosen for accuracy over speed.
- Inference location: fully local on the user's Mac.
- Hotkey: right Option hold-to-record, release-to-transcribe.
- Text output: clipboard preservation plus automatic paste.
- Audio input: system-recognized macOS input devices, including USB-C audio interfaces.

## Architecture

The app is split into a small native shell and a separate local ASR engine.

The Swift app owns the macOS-native responsibilities:

- Menu bar lifecycle and status.
- Permission checks and user guidance.
- Global right Option key monitoring.
- Audio recording from the selected system input device.
- Automatic insertion into the focused text target.

The ASR engine owns model execution:

- Accept a recorded audio file from the Swift app.
- Run Qwen3-ASR-1.7B locally.
- Return plain recognized text.

This separation keeps the native app responsive and makes the recognition backend replaceable later without changing the user-facing workflow.

## Components

### MenuBarApp

Provides the always-running macOS menu bar surface.

Responsibilities:

- Show idle, recording, transcribing, and error states.
- Provide quit and permission-help actions.
- Expose the last transcription for manual copy if automatic paste fails.

### HotkeyMonitor

Detects right Option key press and release globally.

Responsibilities:

- Start recording on right Option down.
- Stop recording on right Option up.
- Ignore repeated key-down events while recording.
- Avoid triggering while the app is already transcribing.

### AudioRecorder

Records microphone input using macOS audio APIs.

Responsibilities:

- Use the current macOS input device by default.
- Support USB-C audio interfaces when they appear as system audio input devices.
- Write a temporary WAV file suitable for ASR input.
- Reject recordings that are empty or too short to transcribe reliably.

### TranscriptionEngine

Runs Qwen3-ASR-1.7B locally.

Responsibilities:

- Receive a local audio file path.
- Run inference in a separate process or isolated local runtime.
- Return UTF-8 Japanese text.
- Report model-missing, runtime, timeout, and unknown failures clearly.

The first implementation may use a local command-line inference runner behind a stable Swift protocol. The protocol boundary should make it possible to move to MLX, Core ML, or another local runtime later.

### PasteInjector

Inserts the recognized text into the focused app.

Responsibilities:

- Capture the current clipboard contents.
- Place the transcription text on the clipboard.
- Send Command-V to the focused application.
- Restore the previous clipboard after paste.
- Preserve the recognized text for manual recovery if paste fails.

### PrivacyGuard

Centralizes privacy-sensitive behavior.

Responsibilities:

- Delete temporary audio files after transcription.
- Avoid logging raw audio paths longer than needed.
- Avoid logging full transcription text.
- Ensure the app does not make network calls for recognition.

## Data Flow

1. `HotkeyMonitor` sees right Option pressed.
2. `AudioRecorder` starts recording from the active macOS input device.
3. `HotkeyMonitor` sees right Option released.
4. `AudioRecorder` stops recording and writes a temporary WAV file.
5. `TranscriptionEngine` sends that WAV file to the local Qwen3-ASR-1.7B runner.
6. The ASR runner returns Japanese text.
7. `PrivacyGuard` schedules or performs audio file deletion.
8. `PasteInjector` preserves the clipboard, pastes the result, and restores the clipboard.
9. `MenuBarApp` returns to idle or shows an error state.

## Permissions

The app needs clear setup guidance for these macOS permissions:

- Microphone: required for recording.
- Accessibility: required for automatic Command-V paste and possibly global key handling.
- Input Monitoring: may be required for reliable global right Option press and release detection.

If a permission is missing, the app should not fail silently. It should show a concise menu bar status and provide a way to open the relevant macOS settings screen when possible.

## Error Handling

The first version handles these cases:

- Missing microphone permission: show setup guidance.
- Missing accessibility or input monitoring permission: show setup guidance.
- No available input device: notify and do not start recording.
- Empty or too-short recording: do not paste; show a lightweight notice.
- Model missing or not configured: show a clear error.
- ASR process failure or timeout: show a clear error and keep the app running.
- Paste failure: restore the clipboard and keep the recognized text available for manual copy.

## Privacy Requirements

- No cloud ASR.
- No external API calls for transcription.
- Audio remains on the Mac.
- Temporary audio files are deleted after transcription or failure cleanup.
- Logs must not contain raw audio content or full transcription text.
- The app should be designed so future cloud backends cannot be added accidentally through the core transcription path.

## Initial Scope

Included:

- macOS menu bar app.
- Right Option hold-to-record interaction.
- Local Qwen3-ASR-1.7B transcription.
- Current system input device recording, including USB-C audio interfaces recognized by macOS.
- Clipboard-preserving automatic paste into the focused text target.
- Basic permission and runtime error handling.
- Privacy-preserving temporary file cleanup.

Not included in the first version:

- Streaming transcription while speaking.
- Speaker diarization.
- Advanced punctuation rewriting.
- Custom dictionaries.
- Cloud sync.
- Model auto-download.
- User-configurable hotkeys.
- Multi-model switching.
- Full settings UI beyond the minimum needed for permissions and status.

## Testing Strategy

Unit-testable boundaries:

- Hotkey state transitions.
- Audio recording state machine.
- Transcription engine protocol behavior with fake runners.
- Clipboard preservation and restoration logic.
- Error mapping from ASR runner failures to user-facing states.

Manual verification:

- Right Option starts and stops recording.
- Releasing right Option triggers transcription.
- Japanese text appears in TextEdit, Safari/Chrome text fields, Notes, and common chat inputs.
- Existing clipboard content is restored after paste.
- USB-C audio interface input works when selected as the macOS input device.
- Temporary audio files are removed after success and failure.
- App behaves clearly when permissions are missing.

## Open Implementation Notes

- The exact Qwen3-ASR-1.7B runtime should be selected during implementation based on current local Mac support, model availability, and Apple Silicon performance.
- The Swift app should define a stable `TranscriptionEngine` protocol before binding to a specific runner.
- The first implementation should optimize correctness and privacy before latency.
