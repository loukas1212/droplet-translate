import Foundation

/// Which engine does the work: the classic models, Apple Intelligence, or a
/// provider on the network. The provider handles its own reach and format.
enum TranslationEngine: String, CaseIterable, Identifiable, Sendable {
    /// More fluent and much slower on long text. First in case order, so it is
    /// the settings' initial and recommended choice.
    case appleIntelligence
    /// A provider on the network, of the user's choosing.
    case provider
    /// The fastest, a little less fluent.
    case classic

    var id: String { rawValue }

    /// The network engine has no local model; the provider's does the work.
    var approach: TranslationApproach? {
        switch self {
        case .classic: return .fast
        case .appleIntelligence: return .accurate
        case .provider: return nil
        }
    }
}

/// Where a translation comes from. Apple's on-device models keep the promise
/// that nothing leaves the Mac; the others are opt-in and say where text goes.
enum TranslationProvider: String, CaseIterable, Identifiable, Sendable {
    case apple
    /// Any endpoint that speaks the OpenAI chat format: OpenAI, Groq,
    /// OpenRouter, Together, LM Studio, vLLM, and the user's own server.
    case openAI
    case anthropic
    case gemini
    /// A local server: no key, and nothing leaves the machine either.
    case ollama
    case custom

    var id: String { rawValue }

    static var aiCases: [TranslationProvider] { allCases.filter { $0 != .apple } }

    var leavesTheDevice: Bool {
        switch self {
        case .apple, .ollama: return false
        case .openAI, .anthropic, .gemini, .custom: return true
        }
    }

    var needsKey: Bool {
        switch self {
        case .apple, .ollama: return false
        case .openAI, .anthropic, .gemini, .custom: return true
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .apple: return ""
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .ollama: return "http://127.0.0.1:11434/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: return ""
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .gemini: return "gemini-1.5-flash"
        case .ollama: return "llama3.2"
        case .custom: return ""
        }
    }

    var wireFormat: WireFormat {
        switch self {
        case .apple, .openAI, .ollama, .custom: return .openAIChat
        case .anthropic: return .anthropicMessages
        case .gemini: return .geminiGenerateContent
        }
    }

    /// The keychain account and the stored preference both use this name.
    var keyAccount: String { "provider.\(rawValue)" }
}

/// The network engine names the provider it would use, so its label has to
/// follow the provider rather than its own case.
extension TranslationEngine {
    /// The catalog key that names this engine. While Apple's models are active
    /// the network engine has no provider yet, so it keeps the generic label
    /// instead of asking for a key that does not exist.
    func nameKey(provider: TranslationProvider) -> String {
        let name = self == .provider && provider != .apple ? provider.rawValue : rawValue
        return "settings.engine.\(name)"
    }
}

/// The request shape a provider speaks.
enum WireFormat: String, Sendable {
    case openAIChat
    case anthropicMessages
    case geminiGenerateContent
}

struct ProviderConfiguration: Sendable {
    var provider: TranslationProvider
    var baseURL: String
    var model: String
    var apiKey: String?

    func endpoint(for provider: TranslationProvider) -> String? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        switch provider.wireFormat {
        case .openAIChat: return base + "/chat/completions"
        case .anthropicMessages: return base + "/messages"
        case .geminiGenerateContent: return base + "/models/\(model):generateContent"
        }
    }
}

/// A translation's worth of work.
struct EngineRequest: Sendable {
    let text: String
    let source: String
    let target: String
}

/// Why a provider could not answer.
enum EngineError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case rateLimited
    case refused(Int, String)
    case noAnswer
    case offline

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L10n.tr("engine.error.notConfigured")
        case .unauthorized: return L10n.tr("engine.error.unauthorized")
        case .rateLimited: return L10n.tr("engine.error.rateLimited")
        case .refused(_, let message): return message
        case .noAnswer: return L10n.tr("engine.error.noAnswer")
        case .offline: return L10n.tr("engine.error.offline")
        }
    }
}

/// The cloud engines: a thin, explicit HTTP call, no SDK and no dependency.
enum TranslationEngines {
    static let requestTimeout: TimeInterval = 30
    static let concurrency = 4
    /// A paragraph reads better than a sentence, and requests run in parallel.
    static let chunkSize = 1500

    static func translate(
        configuration: ProviderConfiguration,
        request: EngineRequest,
        onPartial: @Sendable (String) -> Void
    ) async throws -> String {
        let provider = configuration.provider
        guard provider != .apple else { throw EngineError.notConfigured }
        let key = configuration.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.needsKey, key?.isEmpty != false { throw EngineError.notConfigured }
        guard configuration.endpoint(for: provider) != nil else { throw EngineError.notConfigured }

        let chunks = TextChunker.split(request.text, maxChars: chunkSize)
        guard chunks.count > 1 else {
            return try await send(
                configuration: configuration,
                key: key,
                request: request,
                text: request.text
            )
        }

        // Parallel chunks, capped by `concurrency`; the finished prefix is
        // shown as answers arrive.
        var results = [String?](repeating: nil, count: chunks.count)
        var prefix = 0
        var shown = ""
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            func addTask() {
                guard next < chunks.count else { return }
                let index = next
                next += 1
                let chunk = chunks[index]
                group.addTask {
                    let text = try await send(
                        configuration: configuration,
                        key: key,
                        request: request,
                        text: chunk.text
                    )
                    return (index, text)
                }
            }
            for _ in 0..<min(concurrency, chunks.count) { addTask() }
            while let (index, value) = try await group.next() {
                results[index] = value
                // The prefix only grows: a missing chunk holds the text back.
                while prefix < chunks.count, let next = results[prefix] {
                    shown += next + chunks[prefix].trailing
                    prefix += 1
                    onPartial(shown)
                }
            }
        }
        var full = ""
        for (index, chunk) in chunks.enumerated() {
            full += (results[index] ?? "") + chunk.trailing
        }
        return full
    }

    private static func send(
        configuration: ProviderConfiguration,
        key: String?,
        request: EngineRequest,
        text: String
    ) async throws -> String {
        let provider = configuration.provider
        guard let endpoint = configuration.endpoint(for: provider),
              var url = URL(string: endpoint) else {
            throw EngineError.notConfigured
        }
        if provider.wireFormat == .geminiGenerateContent, let key, !key.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "key", value: key)]
            url = components?.url ?? url
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch provider.wireFormat {
        case .openAIChat:
            urlRequest.setValue("Bearer \(key ?? "")", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": configuration.model,
                "temperature": 0,
                "messages": [
                    ["role": "system", "content": systemPrompt(for: request)],
                    ["role": "user", "content": text]
                ]
            ])
        case .anthropicMessages:
            urlRequest.setValue("x-api-key", forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": configuration.model,
                "max_tokens": 8192,
                "system": systemPrompt(for: request),
                "messages": [["role": "user", "content": text]]
            ])
        case .geminiGenerateContent:
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "systemInstruction": ["parts": [["text": systemPrompt(for: request)]]],
                "contents": [["parts": [["text": text]]]]
            ])
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw EngineError.offline
        } catch {
            throw EngineError.refused(0, error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw EngineError.unauthorized }
        if status == 429 { throw EngineError.rateLimited }
        if !(200..<300).contains(status) {
            throw EngineError.refused(status, String(data: data, encoding: .utf8) ?? "")
        }
        return try extractText(provider: provider, data: data)
    }

    /// The same instruction for every provider. Languages are named rather
    /// than coded: a model asked for "th" would guess.
    private static func systemPrompt(for request: EngineRequest) -> String {
        var prompt = "You are a translation engine. Translate the user's text into \(request.target). "
        if !request.source.isEmpty {
            prompt += "The text is in \(request.source). "
        }
        return prompt
            + "Keep the meaning, the tone and the formatting. "
            + "Answer with the translation only, and nothing else."
    }

    private static func extractText(provider: TranslationProvider, data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EngineError.noAnswer
        }
        let text: String?
        switch provider.wireFormat {
        case .openAIChat:
            let choices = json["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String
        case .anthropicMessages:
            let content = json["content"] as? [[String: Any]]
            text = content?.compactMap { $0["text"] as? String }.joined()
        case .geminiGenerateContent:
            let candidates = json["candidates"] as? [[String: Any]]
            let content = candidates?.first?["content"] as? [String: Any]
            let parts = content?["parts"] as? [[String: Any]]
            text = parts?.compactMap { $0["text"] as? String }.joined()
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngineError.noAnswer
        }
        return text
    }

}
