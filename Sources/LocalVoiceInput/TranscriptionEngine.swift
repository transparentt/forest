import Foundation

protocol TranscriptionEngine: Sendable {
    func warmUp() async
    func transcribe(audioFile: URL) async throws -> String
}

enum TranscriptionError: LocalizedError {
    case runnerMissing(String)
    case invalidServerURL(String)
    case invalidServerResponse
    case timedOut
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .runnerMissing(let path):
            return "ASR runner not found at \(path). Configure a local Qwen3-ASR runner."
        case .invalidServerURL(let value):
            return "Invalid ASR server URL: \(value)."
        case .invalidServerResponse:
            return "Local ASR server returned an invalid response."
        case .timedOut:
            return "Local transcription timed out."
        case .failed(let message):
            return "Local transcription failed: \(message)"
        }
    }
}

extension TranscriptionEngine {
    func warmUp() async {}
}

final class ServerBackedTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    private let config: AppConfig.Transcription
    private let commandEngine: LocalCommandTranscriptionEngine
    private var serverProcess: Process?

    init(config: AppConfig.Transcription) {
        self.config = config
        self.commandEngine = LocalCommandTranscriptionEngine(config: config)
    }

    deinit {
        if serverProcess?.isRunning == true {
            serverProcess?.terminate()
        }
    }

    func warmUp() async {
        // Avoid loading the ASR model at app launch. Qwen3-ASR uses several GB
        // of memory once loaded, so keep launch lightweight and load on demand.
    }

    func transcribe(audioFile: URL) async throws -> String {
        do {
            if try await ensureServer() {
                return try await transcribeViaServer(audioFile: audioFile)
            }
        } catch {
            // Fall back to the command runner below.
        }

        return try await commandEngine.transcribe(audioFile: audioFile)
    }

    private func ensureServer() async throws -> Bool {
        if try await isServerHealthy() {
            return true
        }

        guard FileManager.default.isExecutableFile(atPath: config.serverRunnerPath) else {
            return false
        }

        if serverProcess?.isRunning == true {
            return try await waitForServer()
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.serverRunnerPath)
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTORCH_ENABLE_MPS_FALLBACK": "1",
            "SYSTEM_VERSION_COMPAT": "0"
        ]) { _, new in new }

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        serverProcess = process

        try process.run()
        return try await waitForServer()
    }

    private func waitForServer() async throws -> Bool {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if try await isServerHealthy() {
                return true
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func isServerHealthy() async throws -> Bool {
        let url = try serverURL(path: "/health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 1

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func transcribeViaServer(audioFile: URL) async throws -> String {
        let url = try serverURL(path: "/transcribe?language=Japanese")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = min(config.timeout, 60)

        let data = try Data(contentsOf: audioFile)
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidServerResponse
        }
        guard httpResponse.statusCode == 200 else {
            let message = String(data: responseData, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw TranscriptionError.failed(message)
        }

        let decoded = try JSONDecoder().decode(ServerTranscriptionResponse.self, from: responseData)
        return decoded.text
    }

    private func serverURL(path: String) throws -> URL {
        guard var components = URLComponents(string: config.serverURL) else {
            throw TranscriptionError.invalidServerURL(config.serverURL)
        }
        let split = path.split(separator: "?", maxSplits: 1).map(String.init)
        components.path = split[0]
        if split.count > 1 {
            components.query = split[1]
        }
        guard let url = components.url else {
            throw TranscriptionError.invalidServerURL(config.serverURL)
        }
        return url
    }
}

private struct ServerTranscriptionResponse: Decodable {
    let text: String
}

struct LocalCommandTranscriptionEngine: TranscriptionEngine {
    let config: AppConfig.Transcription

    func transcribe(audioFile: URL) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: config.runnerPath) else {
            throw TranscriptionError.runnerMissing(config.runnerPath)
        }

        let process = ProcessBox(makeProcess(audioFile: audioFile))
        return try await withTaskCancellationHandler {
            try await run(process: process)
        } onCancel: {
            process.terminate()
        }
    }

    private func makeProcess(audioFile: URL) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.runnerPath)
        process.arguments = [audioFile.path]
        return process
    }

    private func run(process: ProcessBox) async throws -> String {
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try process.runAndWait()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(min(config.timeout, 60) * 1_000_000_000))
                process.terminate()
                throw TranscriptionError.timedOut
            }

            guard let result = try await group.next() else {
                throw TranscriptionError.failed("No transcription result.")
            }
            group.cancelAll()
            return result
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) {
        self.process = process
    }

    func runAndWait() throws -> String {
        let stdout = Pipe()
        let stderr = Pipe()

        lock.lock()
        process.standardOutput = stdout
        process.standardError = stderr
        lock.unlock()

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriptionError.failed(message.isEmpty ? "Runner exited with status \(process.terminationStatus)." : message)
        }

        return output
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }

        if process.isRunning {
            process.terminate()
        }
    }
}
