import Testing
@testable import Translate

/// The three languages of the droplet must answer the same questions.
///
/// A key that exists in English and not in French is not a missing string:
/// it is a raw key in the interface, in the middle of a sentence, in front of
/// the user. This is the cheapest test in the project and the one that
/// catches the most.
@Suite("Localization")
struct LocalizationTests {
    private let languages = ["en", "fr", "th"]

    @Test("Every language has the same keys")
    func sameKeys() {
        let english = Set(L10n.strings(for: "en").keys)
        for language in languages {
            let keys = Set(L10n.strings(for: language).keys)
            #expect(keys == english, "\(language) does not have the same keys as English")
        }
    }

    @Test("No string is empty")
    func noEmptyStrings() {
        for language in languages {
            for (key, value) in L10n.strings(for: language) {
                #expect(!value.isEmpty, "\(key) is empty in \(language)")
            }
        }
    }

    @Test("A description ends in a full stop")
    func descriptionsEndInAFullStop() {
        // A description is a sentence and ends like one; a label is a label
        // and does not. The key says which is which.
        for language in ["en", "fr"] {
            for (key, value) in L10n.strings(for: language) {
                guard key.hasSuffix(".sub") || key.hasSuffix(".tip") else { continue }
                #expect(
                    value.hasSuffix(".") || value.hasSuffix("…"),
                    "\(key) in \(language) is a sentence without a full stop"
                )
            }
        }
    }

    @Test("No string has space at its ends or a doubled space")
    func cleanWhitespace() {
        for language in languages {
            for (key, value) in L10n.strings(for: language) {
                #expect(
                    value == value.trimmingCharacters(in: .whitespacesAndNewlines),
                    "\(key) in \(language) has space at its ends"
                )
                #expect(!value.contains("  "), "\(key) in \(language) has a doubled space")
            }
        }
    }

    @Test("A key that is not in the catalog comes back as itself")
    func unknownKey() {
        #expect(L10n.tr("settings.does.not.exist") == "settings.does.not.exist")
    }
}
