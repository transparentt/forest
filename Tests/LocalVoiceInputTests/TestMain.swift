import Foundation

@main
struct TestMain {
    static func main() async throws {
        try testDefaultConfigRoundTrip()
        try testLegacyConfigDecodesWithServerDefaults()
        try testLegacyConfigDecodesWithDefaultHotkey()
        try testLegacyConfigDecodesWithDefaultCustomization()
        try testLegacyCustomizationDecodesWithUnifiedServerDefaults()
        try testCustomizationToggleDecodesExplicitly()
        try testVoiceInstructionDefaultsToOff()
        try testVoiceInstructionAppendCombinesInstructions()
        try testVoiceInstructionReplaceUsesSpokenInstructionOnly()
        try testVoiceInstructionDoesNotEnablePostProcessingWhenCustomizationIsOff()
        try testVoiceInstructionCanEnablePostProcessingWhenCustomizationIsOn()
        try testCustomizationPresetsRoundTrip()
        try testMissingUserDictionaryDecodesWithDefault()
        try testMissingLoggingDecodesEnabled()
        try testLoggingToggleDecodesExplicitly()
        try testPermissionSettingsPresentationExplainsInputMonitoring()
        try testPermissionSettingsPresentationRestoresWindowMoreThanOnce()
        try testUserDictionaryParsesEditableText()
        try testPostProcessingDisabledWhenCustomizationAndDictionaryAreOff()
        try testPostProcessingEnabledWhenDictionaryHasEntries()
        try testPostProcessingEnabledWhenCustomizationIsOn()
        try testPasteInjectorRejectsWhenAccessibilityIsMissing()
        try testProcessingLogStoreRoundTripsEntries()
        try await testTranscriptionWarmUpDoesNotStartServer()
        try await testCustomizationWarmUpDoesNotStartGemma()
        try await testTranscriptionRunnerSuccess()
        try await testTranscriptionRunnerFailure()
        print("All tests passed")
    }

    private static func testDefaultConfigRoundTrip() throws {
        let config = AppConfig.default
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(config)
        let decoded = try decoder.decode(AppConfig.self, from: data)
        try expect(decoded == config, "Default AppConfig should round-trip through JSON.")
    }

    private static func testTranscriptionRunnerSuccess() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let runner = temporaryDirectory.appendingPathComponent("runner.sh")
        try """
        #!/usr/bin/env bash
        echo "今日はテストです。"
        """.write(to: runner, atomically: true, encoding: .utf8)
        try FileManager.default.setExecutable(at: runner)

        let audio = temporaryDirectory.appendingPathComponent("audio.wav")
        try Data([0, 1, 2]).write(to: audio)

        let engine = LocalCommandTranscriptionEngine(
            config: .init(runnerPath: runner.path, timeout: 5)
        )
        let result = try await engine.transcribe(audioFile: audio)
        try expect(result.trimmingCharacters(in: .whitespacesAndNewlines) == "今日はテストです。", "Runner stdout should be returned.")
    }

    private static func testLegacyConfigDecodesWithServerDefaults() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.transcription.runnerPath == "/tmp/runner", "Legacy runnerPath should decode.")
        try expect(config.transcription.serverURL == AppConfig.Transcription.default.serverURL, "Missing serverURL should use default.")
        try expect(config.transcription.serverRunnerPath == AppConfig.Transcription.default.serverRunnerPath, "Missing server runner should use default.")
    }

    private static func testLegacyConfigDecodesWithDefaultHotkey() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.hotkey == .rightOption, "Missing hotkey should use right Option.")
    }

    private static func testLegacyConfigDecodesWithDefaultCustomization() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.customization == .default, "Missing customization should use defaults.")
        try expect(!config.customization.isEnabled, "Default customization should be disabled.")
    }

    private static func testLegacyCustomizationDecodesWithUnifiedServerDefaults() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          },
          "customization": {
            "model": "gemma4",
            "serverURL": "http://127.0.0.1:11434/api/generate",
            "backendURL": "http://127.0.0.1:11434/api/generate",
            "timeout": 12,
            "instruction": "常に敬語にしてください。"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.customization.model == AppConfig.Customization.default.model, "Legacy Gemma model should migrate to the selected default.")
        try expect(config.customization.serverURL == AppConfig.Customization.default.serverURL, "Legacy Ollama serverURL should migrate to the unified Forest server.")
        try expect(config.customization.timeout == AppConfig.Customization.default.timeout, "Short legacy timeout should migrate to the default timeout.")
        try expect(config.customization.instruction == "常に敬語にしてください。", "Customization instruction should be preserved.")
        try expect(config.customization.isEnabled, "Legacy customization with an instruction should stay enabled.")
    }

    private static func testCustomizationToggleDecodesExplicitly() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          },
          "customization": {
            "enabled": false,
            "instruction": "常に敬語にしてください。"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(!config.customization.enabled, "Explicit disabled toggle should decode.")
        try expect(!config.customization.isEnabled, "Disabled toggle should skip customization even when instruction exists.")
    }

    private static func testVoiceInstructionDefaultsToOff() throws {
        let json = """
        {
          "customization": {
            "enabled": true,
            "instruction": "敬語にしてください。"
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(!config.customization.voiceInstructionEnabled, "Missing voice instruction toggle should default to off.")
        try expect(config.customization.voiceInstructionMode == .append, "Missing voice instruction mode should default to append.")
        try expect(config.customization.effectiveInstruction(voiceInstruction: "短くしてください。") == "敬語にしてください。", "Disabled voice instruction should be ignored.")
    }

    private static func testVoiceInstructionAppendCombinesInstructions() throws {
        let customization = AppConfig.Customization(
            enabled: true,
            instruction: "敬語にしてください。",
            voiceInstructionEnabled: true,
            voiceInstructionMode: .append
        )

        try expect(
            customization.effectiveInstruction(voiceInstruction: "箇条書きにしてください。") == "敬語にしてください。\n箇条書きにしてください。",
            "Append mode should combine saved and spoken instructions."
        )
    }

    private static func testVoiceInstructionReplaceUsesSpokenInstructionOnly() throws {
        let customization = AppConfig.Customization(
            enabled: true,
            instruction: "敬語にしてください。",
            voiceInstructionEnabled: true,
            voiceInstructionMode: .replace
        )

        try expect(
            customization.effectiveInstruction(voiceInstruction: "短くしてください。") == "短くしてください。",
            "Replace mode should use only the spoken instruction."
        )
    }

    private static func testVoiceInstructionDoesNotEnablePostProcessingWhenCustomizationIsOff() throws {
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(
                enabled: false,
                instruction: "",
                voiceInstructionEnabled: true,
                voiceInstructionMode: .append
            )
        )

        try expect(!config.customization.usesVoiceInstruction, "Voice instruction should depend on customization being enabled.")
        try expect(!config.needsPostProcessing(voiceInstruction: "句読点を整えてください。"), "Spoken instructions should not trigger post-processing when customization is off.")
        try expect(!config.needsPostProcessing(voiceInstruction: ""), "Empty spoken instructions should not trigger post-processing by themselves.")
    }

    private static func testVoiceInstructionCanEnablePostProcessingWhenCustomizationIsOn() throws {
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(
                enabled: true,
                instruction: "",
                voiceInstructionEnabled: true,
                voiceInstructionMode: .append
            )
        )

        try expect(config.customization.usesVoiceInstruction, "Voice instruction should be active when customization and voice instruction are enabled.")
        try expect(config.needsPostProcessing(voiceInstruction: "句読点を整えてください。"), "Spoken instructions should trigger post-processing when customization is on.")
        try expect(!config.needsPostProcessing(voiceInstruction: ""), "Empty spoken instructions should not trigger post-processing by themselves.")
    }

    private static func testCustomizationPresetsRoundTrip() throws {
        let preset = AppConfig.Customization.Preset(id: "preset-1", name: "敬語", instruction: "敬語にしてください")
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(
                enabled: true,
                instruction: preset.instruction,
                selectedPresetID: preset.id,
                presets: [preset]
            )
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        try expect(decoded.customization.selectedPresetID == "preset-1", "Selected customization preset ID should round-trip.")
        try expect(decoded.customization.presets == [preset], "Customization presets should round-trip.")
    }

    private static func testMissingUserDictionaryDecodesWithDefault() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.userDictionary == .default, "Missing user dictionary should use defaults.")
        try expect(!config.needsPostProcessing, "Default config should not run Gemma post-processing.")
    }

    private static func testMissingLoggingDecodesEnabled() throws {
        let json = """
        {
          "recording": {
            "minimumDuration": 0.35,
            "sampleRate": 16000
          },
          "transcription": {
            "runnerPath": "/tmp/runner",
            "timeout": 120
          },
          "paste": {
            "restoreDelay": 0.5
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(config.logging.enabled, "Missing logging config should default to enabled.")
    }

    private static func testLoggingToggleDecodesExplicitly() throws {
        let json = """
        {
          "logging": {
            "enabled": false
          }
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AppConfig.self, from: json)
        try expect(!config.logging.enabled, "Explicit disabled logging should decode.")
    }

    private static func testPermissionSettingsPresentationExplainsInputMonitoring() throws {
        let text = PermissionSettingsPresentation.inputMonitoringHelpText
        try expect(PermissionSettingsPresentation.inputMonitoringTitle == "入力監視", "Input monitoring title should be separate from status rows.")
        try expect(text.contains("システム設定"), "Input monitoring help should point to System Settings.")
        try expect(text.contains("プライバシーとセキュリティ"), "Input monitoring help should name the privacy section.")
        try expect(text.contains("入力監視"), "Input monitoring help should name Input Monitoring.")
        try expect(text.contains("Forest"), "Input monitoring help should tell the user to check Forest.")
    }

    private static func testPermissionSettingsPresentationRestoresWindowMoreThanOnce() throws {
        try expect(PermissionSettingsPresentation.restoreDelays.count >= 3, "Permission windows should be restored on multiple delayed attempts.")
        try expect(PermissionSettingsPresentation.restoreDelays.first == 0.0, "Permission restore should attempt immediately.")
        try expect(PermissionSettingsPresentation.restoreLevelResetDelay > (PermissionSettingsPresentation.restoreDelays.last ?? 0), "Floating level should reset after the final restore attempt.")
    }

    private static func testUserDictionaryParsesEditableText() throws {
        let entries = AppConfig.UserDictionary.parseEntries(from: """
        あくあぼいす=AquaVoice
        くえん=>Qwen
        ふぉれすと\tForest
        empty
        """)

        try expect(entries == [
            .init(source: "あくあぼいす", target: "AquaVoice"),
            .init(source: "くえん", target: "Qwen"),
            .init(source: "ふぉれすと", target: "Forest")
        ], "Dictionary parser should accept common separators and ignore invalid lines.")
    }

    private static func testPostProcessingDisabledWhenCustomizationAndDictionaryAreOff() throws {
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(enabled: false, instruction: "敬語にしてください"),
            userDictionary: .init(enabled: false, entries: [.init(source: "くえん", target: "Qwen")])
        )

        try expect(!config.needsPostProcessing, "Gemma should not run when both customization and dictionary are off.")
    }

    private static func testPostProcessingEnabledWhenDictionaryHasEntries() throws {
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(enabled: false, instruction: ""),
            userDictionary: .init(enabled: true, entries: [.init(source: "くえん", target: "Qwen")])
        )

        try expect(config.needsPostProcessing, "Dictionary-only processing should run when dictionary is on and has entries.")
    }

    private static func testPostProcessingEnabledWhenCustomizationIsOn() throws {
        let config = AppConfig(
            recording: .default,
            transcription: .default,
            paste: .default,
            customization: .init(enabled: true, instruction: "敬語にしてください"),
            userDictionary: .init(enabled: false, entries: [])
        )

        try expect(config.needsPostProcessing, "Customization-only processing should run when customization is on.")
    }

    private static func testPasteInjectorRejectsWhenAccessibilityIsMissing() throws {
        let injector = ClipboardPasteInjector(pasteDelay: 0, accessibilityPermissionCheck: { false })

        do {
            try injector.paste("入力テスト")
            throw TestFailure("Expected paste to fail when accessibility is missing.")
        } catch let error as PasteInjectorError {
            try expect(error == .accessibilityPermissionMissing, "Missing accessibility should be reported before posting paste events.")
        }
    }

    private static func testTranscriptionWarmUpDoesNotStartServer() async throws {
        let engine = ServerBackedTranscriptionEngine(
            config: .init(
                runnerPath: "/tmp/missing-runner",
                serverRunnerPath: "/tmp/missing-server",
                serverURL: "http://127.0.0.1:9",
                timeout: 1
            )
        )

        await engine.warmUp()
    }

    private static func testCustomizationWarmUpDoesNotStartGemma() async throws {
        let customizer = ServerBackedTextCustomizer()
        await customizer.warmUp()
    }

    private static func testProcessingLogStoreRoundTripsEntries() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = ProcessingLogStore(url: temporaryDirectory.appendingPathComponent("processing-log.jsonl"))
        let entry = ProcessingLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_735_689_600),
            asrDuration: 1.25,
            gemmaDuration: 0.75,
            totalDuration: 2.1,
            asrText: "くえんのモデル",
            gemmaInput: "くえんのモデル",
            finalText: "Qwenのモデル"
        )

        try store.append(entry)

        try expect(store.loadRecent() == [entry], "Processing log should round-trip JSONL entries.")
    }

    private static func testTranscriptionRunnerFailure() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let runner = temporaryDirectory.appendingPathComponent("runner.sh")
        try """
        #!/usr/bin/env bash
        echo "model missing" >&2
        exit 9
        """.write(to: runner, atomically: true, encoding: .utf8)
        try FileManager.default.setExecutable(at: runner)

        let audio = temporaryDirectory.appendingPathComponent("audio.wav")
        try Data([0, 1, 2]).write(to: audio)

        let engine = LocalCommandTranscriptionEngine(
            config: .init(runnerPath: runner.path, timeout: 5)
        )

        do {
            _ = try await engine.transcribe(audioFile: audio)
            throw TestFailure("Expected failing runner to throw.")
        } catch let error as TranscriptionError {
            guard case .failed(let message) = error else {
                throw TestFailure("Expected TranscriptionError.failed, got \(error).")
            }
            try expect(message.contains("model missing"), "stderr should be included in failure message.")
        }
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("localvoiceinput-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
