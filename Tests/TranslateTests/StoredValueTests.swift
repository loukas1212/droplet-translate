import Testing
@testable import Translate

/// The names the droplet stores in the user's preferences are a contract.
///
/// A rename that changes a stored value does not break the build: it
/// silently resets the setting for everyone who already used the droplet. The
/// names are pinned here so that a rename is a deliberate act.
@Suite("The stored values")
struct StoredValueTests {
    @Test("The result destinations keep their names")
    func resultDisplay() {
        #expect(ResultDisplay.normal.rawValue == "normal")
        #expect(ResultDisplay.panel.rawValue == "panel")
        #expect(ResultDisplay.sidePanel.rawValue == "sidePanel")
    }

    @Test("The providers keep their names")
    func providers() {
        #expect(TranslationProvider.apple.rawValue == "apple")
        #expect(TranslationProvider.openAI.rawValue == "openAI")
        #expect(TranslationProvider.anthropic.rawValue == "anthropic")
        #expect(TranslationProvider.gemini.rawValue == "gemini")
        #expect(TranslationProvider.ollama.rawValue == "ollama")
        #expect(TranslationProvider.custom.rawValue == "custom")
    }

    @Test("The qualities keep their names")
    func qualities() {
        #expect(TranslationQuality.fast.rawValue == "fast")
        #expect(TranslationQuality.accurate.rawValue == "accurate")
    }

    @Test("The engines keep their names")
    func engines() {
        #expect(TranslationEngine.classic.rawValue == "classic")
        #expect(TranslationEngine.appleIntelligence.rawValue == "appleIntelligence")
        #expect(TranslationEngine.provider.rawValue == "provider")
    }

    @Test("The panel's content keeps its names")
    func panelContent() {
        #expect(ResultContent.result.rawValue == "result")
        #expect(ResultContent.both.rawValue == "both")
    }
}

/// A translation belongs to the engine that made it: the same text translated
/// by another engine reads differently, so the cache has to know.
@Suite("The cache")
struct CacheTests {
    @Test("A result is not reused for another engine")
    func theEngineIsPartOfTheKey() {
        let text = "Hello"
        let onDevice = TranslateModel.TranslationCacheKey(
            text: text,
            source: "en",
            target: "th",
            engine: "apple"
        )
        let inTheCloud = TranslateModel.TranslationCacheKey(
            text: text,
            source: "en",
            target: "th",
            engine: "provider.openAI"
        )
        #expect(onDevice != inTheCloud)
    }

    @Test("The same text, the same pair and the same engine is the same key")
    func theSameKey() {
        let key = TranslateModel.TranslationCacheKey(
            text: "Hello",
            source: "en",
            target: "th",
            engine: "apple"
        )
        #expect(
            key == TranslateModel.TranslationCacheKey(
                text: "Hello",
                source: "en",
                target: "th",
                engine: "apple"
            )
        )
    }
}
