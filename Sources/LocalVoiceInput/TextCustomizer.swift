import Foundation

protocol TextCustomizer: Sendable {
    func warmUp() async
    func customize(_ text: String) async -> TextCustomizationResult
    func customize(_ text: String, voiceInstruction: String?) async -> TextCustomizationResult
}

struct TextCustomizationResult: Sendable {
    let text: String
    let gemmaDuration: TimeInterval?
    let gemmaModelCheckDuration: TimeInterval?
    let gemmaGenerationDuration: TimeInterval?
    let gemmaInput: String?
}

final class ServerBackedTextCustomizer: TextCustomizer, @unchecked Sendable {
    func warmUp() async {
        // Do not start Gemma at app launch. It can consume significant memory and
        // make the whole desktop stutter. Load on first actual use, then keep
        // Ollama warm via keep_alive on the server side.
    }

    func customize(_ text: String) async -> TextCustomizationResult {
        await customize(text, voiceInstruction: nil)
    }

    func customize(_ text: String, voiceInstruction: String?) async -> TextCustomizationResult {
        let config = AppConfig.load()
        let effectiveInstruction = config.customization.effectiveInstruction(voiceInstruction: voiceInstruction)
        guard config.needsPostProcessing(voiceInstruction: voiceInstruction) else {
            return TextCustomizationResult(
                text: text,
                gemmaDuration: nil,
                gemmaModelCheckDuration: nil,
                gemmaGenerationDuration: nil,
                gemmaInput: nil
            )
        }

        let start = Date()
        do {
            let response = try await customizeViaServer(
                text: text,
                instruction: effectiveInstruction,
                config: config,
                timeout: min(config.customization.timeout, 20)
            )
            let customized = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return TextCustomizationResult(
                text: customized.isEmpty ? text : customized,
                gemmaDuration: Date().timeIntervalSince(start),
                gemmaModelCheckDuration: response.modelCheckDuration,
                gemmaGenerationDuration: response.generationDuration,
                gemmaInput: text
            )
        } catch {
            return TextCustomizationResult(
                text: text,
                gemmaDuration: Date().timeIntervalSince(start),
                gemmaModelCheckDuration: nil,
                gemmaGenerationDuration: nil,
                gemmaInput: text
            )
        }
    }

    private func customizeViaServer(text: String, instruction: String, config: AppConfig, timeout: TimeInterval) async throws -> CustomizationResponse {
        let url = try serverURL(path: "/customize", config: config.customization)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CustomizationRequest(
            model: config.customization.model,
            backendURL: config.customization.backendURL,
            customizationEnabled: !instruction.isEmpty,
            dictionaryEnabled: config.userDictionary.isEnabled,
            instruction: instruction,
            dictionaryEntries: config.userDictionary.isEnabled ? config.userDictionary.entries : [],
            text: text,
            timeout: timeout
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw CustomizationRuntimeError.serverFailed
        }
        return try JSONDecoder().decode(CustomizationResponse.self, from: data)
    }

    private func serverURL(path: String, config: AppConfig.Customization) throws -> URL {
        guard var components = URLComponents(string: config.serverURL) else {
            throw CustomizationRuntimeError.invalidURL
        }
        components.path = path
        guard let url = components.url else {
            throw CustomizationRuntimeError.invalidURL
        }
        return url
    }
}

private struct CustomizationRequest: Encodable {
    let model: String
    let backendURL: String
    let customizationEnabled: Bool
    let dictionaryEnabled: Bool
    let instruction: String
    let dictionaryEntries: [AppConfig.UserDictionary.Entry]
    let text: String
    let timeout: TimeInterval
}

private struct CustomizationResponse: Decodable {
    let text: String
    let modelCheckDuration: TimeInterval?
    let generationDuration: TimeInterval?
}

private enum CustomizationRuntimeError: Error {
    case invalidURL
    case serverFailed
}
