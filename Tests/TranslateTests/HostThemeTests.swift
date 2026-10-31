import AppKit
import Foundation
import Testing
@testable import Translate

/// Which of Droppy's theme settings the card follows.
@Suite("Host theme", .serialized)
struct HostThemeTests {
    @Test("The theme follows the display's own key, then the other one")
    func readsTheKeyForTheDisplay() throws {
        let name = "translate-host-theme-display"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("black", forKey: "externalSurfaceAppearance")
        defaults.set("liquidGlass", forKey: "notchedSurfaceAppearance")

        #expect(HostTheme.read(from: defaults, notched: false) == .black)
        #expect(HostTheme.read(from: defaults, notched: true) == .liquidGlass)

        defaults.removeObject(forKey: "externalSurfaceAppearance")
        #expect(
            HostTheme.read(from: defaults, notched: false) == .liquidGlass,
            "a missing key falls back to the other display's"
        )
    }

    @Test("A defaults change reaches the card while it is on screen")
    @MainActor
    func storeFollowsDefaults() throws {
        let defaults = UserDefaults.standard
        let key = NSScreen.main?.auxiliaryTopLeftArea != nil
            ? "notchedSurfaceAppearance"
            : "externalSurfaceAppearance"
        let old = defaults.string(forKey: key)
        defer {
            if let old { defaults.set(old, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        let store = HostThemeStore()
        let before = store.revision
        defaults.set("black", forKey: key)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(store.current == .black)
        #expect(store.revision > before, "the change did not reach the card")

        let afterFirst = store.revision
        defaults.set("liquidGlass", forKey: key)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        #expect(store.current == .liquidGlass)
        #expect(store.revision > afterFirst, "the second change did not reach the card")
    }

    @Test("An unknown or missing value is Dynamic Glass")
    func fallsBackToDynamicGlass() throws {
        let name = "translate-host-theme-empty"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(HostTheme.read(from: defaults, notched: false) == .dynamicGlass)
        defaults.set("no-such-theme", forKey: "externalSurfaceAppearance")
        #expect(HostTheme.read(from: defaults, notched: false) == .dynamicGlass)
    }
}
