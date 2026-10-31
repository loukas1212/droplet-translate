import Foundation
import Testing
@testable import Translate

/// Every key the code asks for must exist in the catalog.
///
/// A key that is missing does not fail the build: it comes back as itself, and
/// the interface shows `settings.display.sub` in the middle of a sentence.
/// This test reads the sources and checks the names they ask for.
@Suite("The keys the code asks for")
struct KeyUsageTests {
    /// The sources, read at the test's own path.
    private static var sources: [String] {
        // The test bundle sits next to the sources when the package is built
        // in place; the working directory is the package root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TranslateTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // the package
        let folder = root.appendingPathComponent("Sources/Translate")
        // Recursive: a source moved into a subfolder is still a source, and a
        // non-recursive walk drops it without failing, so the keys it asks for
        // would simply stop being checked.
        guard let walker = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return walker
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    /// Every key a source asks for, however it asks for it.
    ///
    /// A key can be asked for directly (`L10n.tr("…")`) or handed to a
    /// helper that takes a key (`sectionHeader("…", "…")`). A key that goes
    /// missing in one way and not the other is a key that shows up raw in the
    /// interface, so both are read.
    private static func keysAskedFor(in source: String) -> [String] {
        var keys: [String] = []
        for match in source.matches(of: /L10n\.tr\("([^"]+)"\)/) {
            keys.append(String(match.output.1))
        }
        for match in source.matches(of: /sectionHeader\("([^"]+)",\s*"([^"]+)"\)/) {
            keys.append(String(match.output.1))
            keys.append(String(match.output.2))
        }
        // A key with an interpolation inside is a family of keys; the family
        // is checked by the keys that do exist.
        return keys.filter { !$0.contains("\\(") }
    }

    /// Every string in the sources that looks like a key of the catalog.
    ///
    /// A key can be asked for directly (`L10n.tr("…")`), handed to a helper
    /// (`sectionHeader("…", "…")`) or held in the model and looked up later
    /// (`titleKey: "…"`). Only the first is a call the compiler can check,
    /// so the last two are read as the plain strings they are.
    private static func keyLikeStrings(in source: String) -> [String] {
        // Only the prefixes the droplet's own strings use: a symbol name or
        // a bundle identifier is not a key.
        let prefixes = [
            "settings.", "permission.", "a11y.",
            "status.", "panel.", "help.", "engine.", "output.", "input."
        ]
        let pattern = /"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)"/
        return source.matches(of: pattern)
            .map { String($0.output.1) }
            .filter { key in prefixes.contains { key.hasPrefix($0) } }
    }

    @Test("Every key the sources name is in the catalog")
    func everyKeyExists() {
        let catalog = L10n.strings(for: "en")
        var missing: Set<String> = []
        for source in Self.sources {
            for key in Self.keysAskedFor(in: source) {
                if catalog[key] == nil { missing.insert(key) }
            }
            for key in Self.keyLikeStrings(in: source) {
                if catalog[key] == nil { missing.insert(key) }
            }
        }
        #expect(missing.isEmpty, "these keys are asked for but not in the catalog: \(missing.sorted())")
    }

    @Test("No key is asked for that the catalog does not have in every language")
    func everyKeyIsInEveryLanguage() {
        let languages = ["en", "fr", "th"]
        for source in Self.sources {
            for key in Self.keysAskedFor(in: source) {
                for language in languages {
                    #expect(
                        L10n.strings(for: language)[key] != nil,
                        "\(key) is missing in \(language)"
                    )
                }
            }
        }
    }
}

/// Every key a family of names builds must exist.
///
/// A key with an interpolation inside (`settings.\(page.rawValue)`) is a
/// family: the compiler sees one name, the interface asks for one key per
/// member, and a member that is missing comes back as itself. The families
/// are listed here with the names they are built from, so a missing member is
/// a red test instead of a raw key on screen.
@Suite("The keys a family of names builds")
struct KeyFamilyTests {
    /// The families, and the names each one is built from.
    private static var families: [(prefix: String, members: [String])] {
        var families: [(prefix: String, members: [String])] = []

        // A page of the droplet's own: its title, and the line under it.
        for page in TranslateSettingsPage.allCases {
            families.append((prefix: "settings.\(page.rawValue)", members: ["", ".sub"]))
        }
        // The engines, and the providers the network engine can be.
        families.append((
            prefix: "settings.engine.",
            members: TranslationEngine.allCases.map(\.rawValue) + TranslationProvider.aiCases.map(\.rawValue)
        ))
        // The rest of the choices the settings offer.
        families.append((prefix: "settings.display.", members: ResultDisplay.allCases.map(\.rawValue)))
        families.append((prefix: "settings.panel.content.", members: ResultContent.allCases.map(\.rawValue)))
        // The state of the language pair, named by a switch and not by an enum.
        families.append((prefix: "settings.pair.", members: ["installed", "needsDownload", "unsupported", "unknown"]))
        return families
    }

    @Test("Every member of every family is in the catalog, in every language")
    func everyMemberExists() {
        let languages = ["en", "fr", "th"]
        var missing: Set<String> = []
        for family in Self.families {
            for member in family.members {
                let key = family.prefix + member
                for language in languages {
                    if L10n.strings(for: language)[key] == nil {
                        missing.insert("\(key) (\(language))")
                    }
                }
            }
        }
        #expect(missing.isEmpty, "these keys are built from a family but not in the catalog: \(missing.sorted())")
    }
}
