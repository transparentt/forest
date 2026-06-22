import AppKit
import Foundation

@MainActor
final class DictationCoordinator {
    private enum RecordingPurpose {
        case dictation
        case voiceInstruction
    }

    private struct TranscriptionResult {
        let text: String
        let duration: TimeInterval
    }

    private let services: AppServices
    private var isRecording = false
    private var isTranscribing = false
    private var isPreparing = true
    private var lastTranscription = ""
    private var meterTimer: Timer?
    private var recordingPurpose: RecordingPurpose?
    private var awaitingVoiceInstruction = false
    private var pendingDictationTask: Task<TranscriptionResult, Error>?
    private var pendingTotalStart: Date?

    init(services: AppServices) {
        self.services = services
    }

    func start() {
        services.statusController.setState(.preparing)
        services.hotkeyMonitor.onRightOptionDown = { [weak self] in
            Task { @MainActor in
                self?.beginRecording()
            }
        }
        services.hotkeyMonitor.onRightOptionUp = { [weak self] in
            Task { @MainActor in
                self?.endRecording()
            }
        }

        do {
            try services.hotkeyMonitor.start()
        } catch {
            services.statusController.setState(.error(error.localizedDescription))
        }

        Task {
            await services.transcriptionEngine.warmUp()
            await services.textCustomizer.warmUp()
            await MainActor.run {
                self.isPreparing = false
                self.services.statusController.setState(.idle)
            }
        }
    }

    func restartHotkeyMonitor() {
        services.hotkeyMonitor.stop()
        do {
            try services.hotkeyMonitor.start()
            services.statusController.setState(.idle)
        } catch {
            services.statusController.setState(.error(error.localizedDescription))
        }
    }

    func copyLastTranscription() {
        guard !lastTranscription.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscription, forType: .string)
    }

    private func beginRecording() {
        guard !isPreparing else {
            services.statusController.setState(.preparing)
            return
        }
        guard !isRecording else { return }
        guard awaitingVoiceInstruction || !isTranscribing else { return }

        let purpose: RecordingPurpose = awaitingVoiceInstruction ? .voiceInstruction : .dictation

        do {
            try services.audioRecorder.start()
            isRecording = true
            recordingPurpose = purpose
            services.statusController.setState(.recording)
            switch purpose {
            case .dictation:
                services.recordingHUD.show()
            case .voiceInstruction:
                services.recordingHUD.showVoiceInstructionRecording()
            }
            startMetering()
        } catch {
            services.statusController.setState(.error(error.localizedDescription))
        }
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        let purpose = recordingPurpose ?? .dictation
        recordingPurpose = nil
        stopMetering()
        services.recordingHUD.hide()

        do {
            let recording = try services.audioRecorder.stop()
            guard recording.duration >= services.config.recording.minimumDuration else {
                try? FileManager.default.removeItem(at: recording.url)
                if purpose == .voiceInstruction {
                    finishVoiceInstruction(recording: nil)
                } else {
                    services.statusController.setState(.idle)
                }
                return
            }

            switch purpose {
            case .dictation:
                if AppConfig.load().customization.usesVoiceInstruction {
                    beginVoiceInstructionPhase(dictationRecording: recording)
                } else {
                    isTranscribing = true
                    services.statusController.setState(.transcribing)
                    services.recordingHUD.showTranscribing(isWarmup: true)

                    Task {
                        await transcribeAndPaste(recording: recording)
                    }
                }
            case .voiceInstruction:
                services.statusController.setState(.transcribing)
                services.recordingHUD.showVoiceInstructionTranscribing()
                finishVoiceInstruction(recording: recording)
            }
        } catch {
            services.statusController.setState(.error(error.localizedDescription))
        }
    }

    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.services.recordingHUD.update(level: self.services.audioRecorder.currentLevel())
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func beginVoiceInstructionPhase(dictationRecording: AudioRecording) {
        pendingTotalStart = Date()
        awaitingVoiceInstruction = true
        isTranscribing = true
        services.statusController.setState(.transcribing)
        services.recordingHUD.showTranscribing(isWarmup: true)

        pendingDictationTask = Task {
            try await transcribe(recording: dictationRecording)
        }
    }

    private func finishVoiceInstruction(recording: AudioRecording?) {
        awaitingVoiceInstruction = false

        Task {
            await transcribeVoiceInstructionAndPaste(recording: recording)
        }
    }

    private func transcribeAndPaste(recording: AudioRecording) async {
        let totalStart = Date()

        do {
            let result = try await transcribe(recording: recording)
            await paste(result: result, voiceInstruction: nil, totalStart: totalStart)
        } catch {
            await MainActor.run {
                self.isTranscribing = false
                self.services.recordingHUD.hide()
                self.services.statusController.setState(.error(error.localizedDescription))
            }
        }
    }

    private func transcribeVoiceInstructionAndPaste(recording: AudioRecording?) async {
        defer {
            pendingDictationTask = nil
            pendingTotalStart = nil
        }

        do {
            let voiceInstruction: String?
            if let recording {
                let voiceResult = try await transcribe(recording: recording)
                voiceInstruction = voiceResult.text
            } else {
                voiceInstruction = nil
            }

            guard let pendingDictationTask else {
                throw TranscriptionFlowError.missingDictation
            }
            let dictationResult = try await pendingDictationTask.value
            await paste(
                result: dictationResult,
                voiceInstruction: voiceInstruction,
                totalStart: pendingTotalStart ?? Date()
            )
        } catch {
            await MainActor.run {
                self.isTranscribing = false
                self.services.recordingHUD.hide()
                self.services.statusController.setState(.error(error.localizedDescription))
            }
        }
    }

    private func transcribe(recording: AudioRecording) async throws -> TranscriptionResult {
        defer {
            try? FileManager.default.removeItem(at: recording.url)
        }

        let asrStart = Date()
        let text = try await services.transcriptionEngine.transcribe(audioFile: recording.url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(text: text, duration: Date().timeIntervalSince(asrStart))
    }

    private func paste(result: TranscriptionResult, voiceInstruction: String?, totalStart: Date) async {
        let config = AppConfig.load()
        if config.needsPostProcessing(voiceInstruction: voiceInstruction) {
            await MainActor.run {
                self.services.recordingHUD.showTranscribing()
            }
        }
        let customization = await services.textCustomizer.customize(result.text, voiceInstruction: voiceInstruction)
        let finalText = customization.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalDuration = Date().timeIntervalSince(totalStart)

        if AppConfig.load().logging.enabled {
            try? services.logStore.append(ProcessingLogEntry(
                timestamp: Date(),
                asrDuration: result.duration,
                gemmaDuration: customization.gemmaDuration,
                gemmaModelCheckDuration: customization.gemmaModelCheckDuration,
                gemmaGenerationDuration: customization.gemmaGenerationDuration,
                totalDuration: totalDuration,
                asrText: result.text,
                gemmaInput: customization.gemmaInput,
                finalText: finalText
            ))
        }

        await MainActor.run {
            self.isTranscribing = false
            self.services.recordingHUD.hide()
            guard !finalText.isEmpty else {
                self.services.statusController.setState(.idle)
                return
            }

            self.lastTranscription = finalText
            do {
                try self.services.pasteInjector.paste(finalText)
                self.services.statusController.setState(.idle)
            } catch {
                self.services.statusController.setState(.error(error.localizedDescription))
            }
        }
    }
}

private enum TranscriptionFlowError: LocalizedError {
    case missingDictation

    var errorDescription: String? {
        switch self {
        case .missingDictation:
            return "本文の音声認識を開始できませんでした。"
        }
    }
}
