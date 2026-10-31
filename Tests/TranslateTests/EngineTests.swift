import Testing
@testable import Translate

/// The engine's own decisions, which are pure and therefore testable: which
/// models each engine uses, where a provider is called, and how a long text
/// is cut into pieces.
@Suite("The engine")
struct EngineTests {
    @Test("The classic engine uses the fast models")
    func classicEngine() {
        #expect(TranslationEngine.classic.approach == .fast)
    }

    @Test("The Apple Intelligence engine uses the accurate models")
    func appleIntelligenceEngine() {
        #expect(TranslationEngine.appleIntelligence.approach == .accurate)
    }

    @Test("The network engine uses no models of its own")
    func networkEngine() {
        #expect(TranslationEngine.provider.approach == nil)
    }

    /// Every engine label the panel can show must resolve to a string; a
    /// missing key shows up raw, as `settings.engine.apple` did for the
    /// network engine before a provider was picked.
    @Test("Every engine name has a string")
    func engineNamesExist() {
        let previous = L10n.override
        L10n.override = "en"
        defer { L10n.override = previous }
        for engine in TranslationEngine.allCases {
            for provider in TranslationProvider.allCases {
                let key = engine.nameKey(provider: provider)
                #expect(L10n.tr(key) != key, "\(key) has no string")
            }
        }
    }

    @Test("A chosen quality is used whatever the text is")
    func chosenQuality() {
        #expect(TranslationQuality.fast.approach == .fast)
        #expect(TranslationQuality.accurate.approach == .accurate)
    }

    @Test("A provider's endpoint is its own address plus its path")
    func endpoints() {
        #expect(
            ProviderConfiguration(
                provider: .openAI,
                baseURL: "https://api.openai.com/v1",
                model: "gpt-4o-mini",
                apiKey: nil
            ).endpoint(for: .openAI) == "https://api.openai.com/v1/chat/completions"
        )
        #expect(
            ProviderConfiguration(
                provider: .anthropic,
                baseURL: "https://api.anthropic.com/v1",
                model: "claude-3-5-haiku-latest",
                apiKey: nil
            ).endpoint(for: .anthropic) == "https://api.anthropic.com/v1/messages"
        )
        #expect(
            ProviderConfiguration(
                provider: .gemini,
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                model: "gemini-1.5-flash",
                apiKey: nil
            ).endpoint(for: .gemini) == "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
        )
    }

    @Test("An empty address has no endpoint")
    func noEndpointWithoutAnAddress() {
        let configuration = ProviderConfiguration(
            provider: .custom,
            baseURL: "   ",
            model: "a-model",
            apiKey: nil
        )
        #expect(configuration.endpoint(for: .custom) == nil)
    }

    @Test("Only the local engines keep the text on the machine")
    func whatLeavesTheMachine() {
        #expect(TranslationProvider.apple.leavesTheDevice == false)
        #expect(TranslationProvider.ollama.leavesTheDevice == false)
        #expect(TranslationProvider.openAI.leavesTheDevice == true)
        #expect(TranslationProvider.anthropic.leavesTheDevice == true)
        #expect(TranslationProvider.gemini.leavesTheDevice == true)
        #expect(TranslationProvider.custom.leavesTheDevice == true)
    }

    @Test("Only the local engines need no key")
    func whoNeedsAKey() {
        #expect(TranslationProvider.apple.needsKey == false)
        #expect(TranslationProvider.ollama.needsKey == false)
        #expect(TranslationProvider.openAI.needsKey == true)
        #expect(TranslationProvider.anthropic.needsKey == true)
        #expect(TranslationProvider.gemini.needsKey == true)
        #expect(TranslationProvider.custom.needsKey == true)
    }

    @Test("A built-in provider's address is its own")
    func defaultAddresses() {
        #expect(TranslationProvider.openAI.defaultBaseURL == "https://api.openai.com/v1")
        #expect(TranslationProvider.anthropic.defaultBaseURL == "https://api.anthropic.com/v1")
        #expect(TranslationProvider.gemini.defaultBaseURL == "https://generativelanguage.googleapis.com/v1beta")
        #expect(TranslationProvider.ollama.defaultBaseURL == "http://127.0.0.1:11434/v1")
        #expect(TranslationProvider.custom.defaultBaseURL == "")
    }

    @Test("The AI engine's providers are the ones that are not Apple's")
    func aiProviders() {
        #expect(TranslationProvider.aiCases.contains(.openAI))
        #expect(TranslationProvider.aiCases.contains(.anthropic))
        #expect(TranslationProvider.aiCases.contains(.gemini))
        #expect(TranslationProvider.aiCases.contains(.ollama))
        #expect(TranslationProvider.aiCases.contains(.custom))
        #expect(!TranslationProvider.aiCases.contains(.apple))
    }
}

/// A long text is cut into pieces the engine can answer one by one, and not
/// one character is lost or doubled in the cutting.
@Suite("The chunker")
struct TextChunkerTests {
    @Test("A short text is one piece")
    func shortText() {
        let chunks = TextChunker.split("Hello there.")
        #expect(chunks.count == 1)
        #expect(chunks.first?.text == "Hello there.")
        #expect(chunks.first?.trailing == "")
    }

    @Test("The pieces put the text back together")
    func nothingIsLost() {
        let text = """
        The first sentence is here. The second one follows it, and it is a \
        little longer than the first. A third one arrives to make the text \
        long enough to be cut.
        """
        let chunks = TextChunker.split(text, maxChars: 40)
        #expect(chunks.count > 1)
        // The engine puts the translation back in front of the piece's own
        // whitespace, so that is the order the text comes back in.
        let rebuilt = chunks.map { $0.text + $0.trailing }.joined()
        #expect(rebuilt == text)
    }

    @Test("No piece is longer than the limit, except one without a word to cut")
    func piecesAreShortEnough() {
        let text = String(repeating: "A sentence of a few words. ", count: 40)
        for chunk in TextChunker.split(text, maxChars: 60) {
            #expect(chunk.text.count <= 60 || !chunk.text.contains(" "))
        }
    }

    @Test("The whitespace between the pieces is kept")
    func whitespaceIsKept() {
        let text = "First one here.\n\nSecond one here.\n"
        let chunks = TextChunker.split(text, maxChars: 20)
        #expect(chunks.map { $0.text + $0.trailing }.joined() == text)
    }
}
