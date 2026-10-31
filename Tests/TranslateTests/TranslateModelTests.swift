import Testing
@testable import Translate

/// The pin: it holds the shelf open, and it is released when the shelf is
/// closed and nothing else is holding it.
@Suite("The pin")
@MainActor
struct PinTests {
    @Test("The pin is released when the shelf closes")
    func releasedOnClose() {
        #expect(TranslateModel.shouldReleasePin(
            isPinned: true,
            suspended: false,
            shelfWasExpanded: true,
            shelfIsClosed: true
        ))
    }

    @Test("The pin is held while the shelf is open")
    func heldWhileOpen() {
        #expect(!TranslateModel.shouldReleasePin(
            isPinned: true,
            suspended: false,
            shelfWasExpanded: true,
            shelfIsClosed: false
        ))
        #expect(!TranslateModel.shouldReleasePin(
            isPinned: true,
            suspended: false,
            shelfWasExpanded: false,
            shelfIsClosed: true
        ))
    }

    @Test("An unpinned shelf is never released by the pin")
    func nothingToRelease() {
        #expect(!TranslateModel.shouldReleasePin(
            isPinned: false,
            suspended: false,
            shelfWasExpanded: true,
            shelfIsClosed: true
        ))
    }

    @Test("A suspended pin is not released")
    func suspended() {
        #expect(!TranslateModel.shouldReleasePin(
            isPinned: true,
            suspended: true,
            shelfWasExpanded: true,
            shelfIsClosed: true
        ))
    }
}

/// The swap disc: an explicit pair trades places, and an automatic source
/// never leaves the disc with nothing to do.
@Suite("The swap")
@MainActor
struct SwapTests {
    @Test("An explicit pair trades places")
    func explicitPair() {
        let model = TranslateModel()
        model.sourceID = "en"
        model.targetID = "th"
        #expect(model.canSwap)
        model.swapLanguageSelection()
        #expect(model.sourceID == "th")
        #expect(model.targetID == "en")
    }

    @Test("An automatic source swaps with a fallback before any text is seen")
    func automaticSource() {
        let model = TranslateModel()
        #expect(model.sourceID == TranslateModel.auto)
        #expect(model.targetID == "en")
        #expect(model.canSwap)
        model.swapLanguageSelection()
        #expect(model.sourceID == "en")
        #expect(model.targetID != "en")
        #expect(!LanguageTools.isSameLanguage(model.targetID, "en"))
    }

    @Test("The same language on both sides cannot swap")
    func samePair() {
        let model = TranslateModel()
        model.sourceID = "en"
        model.targetID = "en"
        #expect(!model.canSwap)
        model.swapLanguageSelection()
        #expect(model.sourceID == "en")
        #expect(model.targetID == "en")
    }
}

/// The result has several homes, and the one on the notch lives as long as it
/// is told to.
@Suite("The result")
@MainActor
struct ResultTests {
    @Test("The result has all its destinations")
    func destinations() {
        #expect(ResultDisplay.allCases.count == 3)
        #expect(ResultDisplay.allCases.contains(.normal))
        #expect(ResultDisplay.allCases.contains(.panel))
        #expect(ResultDisplay.allCases.contains(.sidePanel))
    }

    @Test("A capture waits while translating and routes successful results externally")
    func capturedResultRouting() {
        #expect(TranslateModel.captureResultRoute(
            display: .sidePanel,
            status: .translating,
            resultReady: false,
            canWaitForTranslation: true
        ) == .wait)
        #expect(TranslateModel.captureResultRoute(
            display: .panel,
            status: .idle,
            resultReady: true,
            canWaitForTranslation: false
        ) == .selectedDestination)
        #expect(TranslateModel.captureResultRoute(
            display: .sidePanel,
            status: .sameLanguage,
            resultReady: true,
            canWaitForTranslation: false
        ) == .selectedDestination)
        #expect(TranslateModel.captureResultRoute(
            display: .normal,
            status: .idle,
            resultReady: true,
            canWaitForTranslation: false
        ) == .shelf)
        #expect(TranslateModel.captureResultRoute(
            display: .sidePanel,
            status: .idle,
            resultReady: true,
            canWaitForTranslation: false
        ) == .selectedDestination)
    }

    @Test("External destinations keep downloads and failures in their selected home")
    func externalDestinationsKeepTerminalStatuses() {
        for status in [
            TranslateModel.Status.needsDownload,
            .unsupported,
            .undetected,
            .failed,
            .osTooOld
        ] {
            #expect(TranslateModel.captureResultRoute(
                display: .panel,
                status: status,
                resultReady: false,
                canWaitForTranslation: false
            ) == .selectedDestination)
            #expect(TranslateModel.captureResultRoute(
                display: .sidePanel,
                status: status,
                resultReady: false,
                canWaitForTranslation: false
            ) == .selectedDestination)
            #expect(TranslateModel.captureResultRoute(
                display: .normal,
                status: status,
                resultReady: false,
                canWaitForTranslation: false
            ) == .shelf)
        }
        #expect(TranslateModel.captureResultRoute(
            display: .panel,
            status: .translating,
            resultReady: false,
            canWaitForTranslation: false
        ) == .shelf)
    }
}

/// The languages of the droplet are named the way the system names them, so
/// that a name in the menu is the name the system shows.
@Suite("The languages")
struct LanguageTests {
    @Test("A language is named by its code")
    func canonicalIdentifiers() {
        #expect(LanguageTools.canonicalID("th-TH") == "th")
        #expect(LanguageTools.canonicalID("en-US") == "en")
        #expect(LanguageTools.canonicalID("fr") == "fr")
    }

    @Test("A language has a name")
    func names() {
        #expect(!LanguageTools.name(for: "th").isEmpty)
        #expect(!LanguageTools.name(for: "en").isEmpty)
    }
}

/// The droplet's own limits, in one place.
@Suite("The limits")
@MainActor
struct LimitTests {
    @Test("The text is cut at five thousand characters")
    func inputLimit() {
        #expect(TranslateModel.maxInputLength == 5000)
    }
}
