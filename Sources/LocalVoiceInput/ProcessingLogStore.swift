import Foundation

struct ProcessingLogEntry: Codable, Equatable, Sendable {
    let timestamp: Date
    let asrDuration: TimeInterval
    let gemmaDuration: TimeInterval?
    let gemmaModelCheckDuration: TimeInterval?
    let gemmaGenerationDuration: TimeInterval?
    let totalDuration: TimeInterval
    let asrText: String
    let gemmaInput: String?
    let finalText: String

    init(
        timestamp: Date,
        asrDuration: TimeInterval,
        gemmaDuration: TimeInterval?,
        gemmaModelCheckDuration: TimeInterval? = nil,
        gemmaGenerationDuration: TimeInterval? = nil,
        totalDuration: TimeInterval,
        asrText: String,
        gemmaInput: String?,
        finalText: String
    ) {
        self.timestamp = timestamp
        self.asrDuration = asrDuration
        self.gemmaDuration = gemmaDuration
        self.gemmaModelCheckDuration = gemmaModelCheckDuration
        self.gemmaGenerationDuration = gemmaGenerationDuration
        self.totalDuration = totalDuration
        self.asrText = asrText
        self.gemmaInput = gemmaInput
        self.finalText = finalText
    }
}

struct ProcessingLogStore: Sendable {
    let url: URL

    static let `default` = ProcessingLogStore(
        url: AppConfig.configDirectoryURL.appendingPathComponent("processing-log.jsonl")
    )

    func append(_ entry: ProcessingLogEntry) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line = try encoder.encode(entry) + Data([0x0A])

        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    func loadRecent(limit: Int = 100) -> [ProcessingLogEntry] {
        guard
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(whereSeparator: \.isNewline)
            .suffix(limit)
            .compactMap { line in
                try? decoder.decode(ProcessingLogEntry.self, from: Data(String(line).utf8))
            }
    }
}
