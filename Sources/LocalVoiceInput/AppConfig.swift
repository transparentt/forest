import Foundation

struct AppConfig: Codable, Equatable, Sendable {
    struct Recording: Codable, Equatable, Sendable {
        let minimumDuration: TimeInterval
        let sampleRate: Double

        static let `default` = Recording(minimumDuration: 0.35, sampleRate: 16_000)
    }

    struct Transcription: Codable, Equatable, Sendable {
        let runnerPath: String
        let serverRunnerPath: String
        let serverURL: String
        let timeout: TimeInterval

        static let `default` = Transcription(
            runnerPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".localvoiceinput/bin/qwen3_asr_transcribe.py")
                .path,
            serverRunnerPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".localvoiceinput/bin/qwen3_asr_server.py")
                .path,
            serverURL: "http://127.0.0.1:8765",
            timeout: 180
        )

        init(runnerPath: String, serverRunnerPath: String? = nil, serverURL: String? = nil, timeout: TimeInterval) {
            self.runnerPath = runnerPath
            self.serverRunnerPath = serverRunnerPath ?? Self.default.serverRunnerPath
            self.serverURL = serverURL ?? Self.default.serverURL
            self.timeout = timeout
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.runnerPath = try container.decodeIfPresent(String.self, forKey: .runnerPath) ?? Self.default.runnerPath
            self.serverRunnerPath = try container.decodeIfPresent(String.self, forKey: .serverRunnerPath) ?? Self.default.serverRunnerPath
            self.serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? Self.default.serverURL
            self.timeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? Self.default.timeout
        }
    }

    struct Paste: Codable, Equatable, Sendable {
        let restoreDelay: TimeInterval

        static let `default` = Paste(restoreDelay: 0.5)
    }

    struct Hotkey: Codable, Equatable, Sendable {
        let keyCode: Int
        let displayName: String

        static let rightOption = Hotkey(keyCode: 61, displayName: "右Option")
        static let `default` = rightOption
    }

    struct Customization: Codable, Equatable, Sendable {
        enum VoiceInstructionMode: String, Codable, Equatable, Sendable {
            case append
            case replace

            var displayName: String {
                switch self {
                case .append:
                    return "事前の指示に追加"
                case .replace:
                    return "音声指示で上書き"
                }
            }
        }

        struct Preset: Codable, Equatable, Identifiable, Sendable {
            let id: String
            let name: String
            let instruction: String

            init(id: String = UUID().uuidString, name: String, instruction: String) {
                self.id = id
                self.name = name
                self.instruction = instruction
            }
        }

        let enabled: Bool
        let model: String
        let serverURL: String
        let backendURL: String
        let timeout: TimeInterval
        let instruction: String
        let selectedPresetID: String?
        let presets: [Preset]
        let voiceInstructionEnabled: Bool
        let voiceInstructionMode: VoiceInstructionMode

        static let `default` = Customization(
            enabled: false,
            model: "gemma4:e4b",
            serverURL: "http://127.0.0.1:8765",
            backendURL: "http://127.0.0.1:11434/api/generate",
            timeout: 45,
            instruction: "",
            selectedPresetID: nil,
            presets: [],
            voiceInstructionEnabled: false,
            voiceInstructionMode: .append
        )

        var isEnabled: Bool {
            enabled && !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var usesVoiceInstruction: Bool {
            enabled && voiceInstructionEnabled
        }

        func effectiveInstruction(voiceInstruction: String?) -> String {
            let baseInstruction = isEnabled ? instruction.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let spokenInstruction = usesVoiceInstruction
                ? (voiceInstruction ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            guard !spokenInstruction.isEmpty else {
                return baseInstruction
            }

            switch voiceInstructionMode {
            case .append:
                guard !baseInstruction.isEmpty else { return spokenInstruction }
                return "\(baseInstruction)\n\(spokenInstruction)"
            case .replace:
                return spokenInstruction
            }
        }

        init(
            enabled: Bool? = nil,
            model: String? = nil,
            serverURL: String? = nil,
            backendURL: String? = nil,
            timeout: TimeInterval? = nil,
            instruction: String? = nil,
            selectedPresetID: String? = nil,
            presets: [Preset]? = nil,
            voiceInstructionEnabled: Bool? = nil,
            voiceInstructionMode: VoiceInstructionMode? = nil
        ) {
            self.enabled = enabled ?? Self.default.enabled
            self.model = model ?? Self.default.model
            self.serverURL = serverURL ?? Self.default.serverURL
            self.backendURL = backendURL ?? Self.default.backendURL
            self.timeout = timeout ?? Self.default.timeout
            self.instruction = instruction ?? Self.default.instruction
            self.selectedPresetID = selectedPresetID
            self.presets = presets ?? Self.default.presets
            self.voiceInstructionEnabled = voiceInstructionEnabled ?? Self.default.voiceInstructionEnabled
            self.voiceInstructionMode = voiceInstructionMode ?? Self.default.voiceInstructionMode
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedModel = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
            self.model = decodedModel == "gemma4" ? Self.default.model : decodedModel
            let decodedServerURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? Self.default.serverURL
            self.serverURL = Self.normalizedServerURL(decodedServerURL)
            self.backendURL = try container.decodeIfPresent(String.self, forKey: .backendURL) ?? Self.default.backendURL
            let decodedTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .timeout) ?? Self.default.timeout
            self.timeout = max(decodedTimeout, Self.default.timeout)
            self.instruction = try container.decodeIfPresent(String.self, forKey: .instruction) ?? Self.default.instruction
            self.selectedPresetID = try container.decodeIfPresent(String.self, forKey: .selectedPresetID)
            self.presets = try container.decodeIfPresent([Preset].self, forKey: .presets) ?? Self.default.presets
            self.voiceInstructionEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceInstructionEnabled) ?? Self.default.voiceInstructionEnabled
            self.voiceInstructionMode = try container.decodeIfPresent(VoiceInstructionMode.self, forKey: .voiceInstructionMode) ?? Self.default.voiceInstructionMode
            self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
                ?? !self.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private static func normalizedServerURL(_ value: String) -> String {
            if value == "http://127.0.0.1:8766" {
                return Self.default.serverURL
            }

            guard let components = URLComponents(string: value) else {
                return Self.default.serverURL
            }

            if components.port == 11434 || components.path == "/api/generate" {
                return Self.default.serverURL
            }

            return value
        }
    }

    struct UserDictionary: Codable, Equatable, Sendable {
        struct Entry: Codable, Equatable, Sendable {
            let source: String
            let target: String

            init(source: String, target: String) {
                self.source = source
                self.target = target
            }
        }

        let enabled: Bool
        let entries: [Entry]

        static let `default` = UserDictionary(enabled: false, entries: [])

        var isEnabled: Bool {
            enabled && entries.contains { !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        init(enabled: Bool? = nil, entries: [Entry]? = nil) {
            self.enabled = enabled ?? Self.default.enabled
            self.entries = entries ?? Self.default.entries
        }

        static func parseEntries(from text: String) -> [Entry] {
            text
                .split(whereSeparator: \.isNewline)
                .compactMap { rawLine in
                    let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !line.isEmpty else { return nil }

                    for separator in ["=>", "=", "\t", ","] {
                        guard let range = line.range(of: separator) else { continue }
                        let source = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let target = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !source.isEmpty, !target.isEmpty else { return nil }
                        return Entry(source: source, target: target)
                    }

                    return nil
                }
        }

        var editableText: String {
            entries
                .map { "\($0.source)=\($0.target)" }
                .joined(separator: "\n")
        }
    }

    struct Logging: Codable, Equatable, Sendable {
        let enabled: Bool

        static let `default` = Logging(enabled: true)

        init(enabled: Bool? = nil) {
            self.enabled = enabled ?? Self.default.enabled
        }
    }

    let recording: Recording
    let transcription: Transcription
    let paste: Paste
    let hotkey: Hotkey
    let customization: Customization
    let userDictionary: UserDictionary
    let logging: Logging

    static let `default` = AppConfig(
        recording: .default,
        transcription: .default,
        paste: .default,
        hotkey: .default,
        customization: .default,
        userDictionary: .default,
        logging: .default
    )

    var needsPostProcessing: Bool {
        customization.isEnabled || userDictionary.isEnabled
    }

    func needsPostProcessing(voiceInstruction: String?) -> Bool {
        userDictionary.isEnabled || !customization.effectiveInstruction(voiceInstruction: voiceInstruction).isEmpty
    }

    init(
        recording: Recording,
        transcription: Transcription,
        paste: Paste,
        hotkey: Hotkey = .default,
        customization: Customization = .default,
        userDictionary: UserDictionary = .default,
        logging: Logging = .default
    ) {
        self.recording = recording
        self.transcription = transcription
        self.paste = paste
        self.hotkey = hotkey
        self.customization = customization
        self.userDictionary = userDictionary
        self.logging = logging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.recording = try container.decodeIfPresent(Recording.self, forKey: .recording) ?? .default
        self.transcription = try container.decodeIfPresent(Transcription.self, forKey: .transcription) ?? .default
        self.paste = try container.decodeIfPresent(Paste.self, forKey: .paste) ?? .default
        self.hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? .default
        self.customization = try container.decodeIfPresent(Customization.self, forKey: .customization) ?? .default
        self.userDictionary = try container.decodeIfPresent(UserDictionary.self, forKey: .userDictionary) ?? .default
        self.logging = try container.decodeIfPresent(Logging.self, forKey: .logging) ?? .default
    }

    static func load() -> AppConfig {
        let url = configURL

        guard let data = try? Data(contentsOf: url) else {
            return .default
        }

        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return .default
        }
    }

    static var configDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".localvoiceinput", isDirectory: true)
    }

    static var configURL: URL {
        configDirectoryURL.appendingPathComponent("config.json")
    }

    static func createDefaultConfigIfMissing() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: configURL.path) else {
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(AppConfig.default)
        try data.write(to: configURL, options: .atomic)
    }

    static func save(_ config: AppConfig) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: configDirectoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    static func saveHotkey(_ hotkey: Hotkey) throws {
        let current = load()
        try save(AppConfig(
            recording: current.recording,
            transcription: current.transcription,
            paste: current.paste,
            hotkey: hotkey,
            customization: current.customization,
            userDictionary: current.userDictionary,
            logging: current.logging
        ))
    }

    static func saveCustomization(_ customization: Customization) throws {
        let current = load()
        try save(AppConfig(
            recording: current.recording,
            transcription: current.transcription,
            paste: current.paste,
            hotkey: current.hotkey,
            customization: customization,
            userDictionary: current.userDictionary,
            logging: current.logging
        ))
    }

    static func saveUserDictionary(_ userDictionary: UserDictionary) throws {
        let current = load()
        try save(AppConfig(
            recording: current.recording,
            transcription: current.transcription,
            paste: current.paste,
            hotkey: current.hotkey,
            customization: current.customization,
            userDictionary: userDictionary,
            logging: current.logging
        ))
    }

    static func saveLogging(_ logging: Logging) throws {
        let current = load()
        try save(AppConfig(
            recording: current.recording,
            transcription: current.transcription,
            paste: current.paste,
            hotkey: current.hotkey,
            customization: current.customization,
            userDictionary: current.userDictionary,
            logging: logging
        ))
    }
}
