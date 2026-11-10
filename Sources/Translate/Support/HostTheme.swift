import AppKit
import Combine
import Foundation

/// The surface theme the user picked in Droppy for the shelf and panels.
/// DroppyKit publishes only dark or light, so read the host's setting with
/// `externalSurfaceAppearance`, not the notch key: the two can differ.
enum HostTheme: String, Equatable {
    case black
    case liquidGlass
    case dynamicGlass

    static func read(from defaults: UserDefaults = .standard) -> HostTheme {
        let raw = defaults.string(forKey: "externalSurfaceAppearance")
            ?? defaults.string(forKey: "notchedSurfaceAppearance")
        return raw.flatMap(HostTheme.init(rawValue:)) ?? .dynamicGlass
    }
}

/// Redraws open cards when Droppy's theme changes. The host's notification is
/// the main signal; defaults and a slow poll catch a silent write.
final class HostThemeStore: ObservableObject {
    /// The theme the host is drawing its surfaces in now.
    @Published private(set) var current = HostTheme.read()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UserDefaults.didChangeNotification,
            NSApplication.didBecomeActiveNotification,
            // The host repaints its surfaces on this one, so a theme picked
            // while the card is open reaches the picture at once.
            Notification.Name("DroppySurfaceAppearanceDidChange")
        ]
        for name in names {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
        // A host that writes its theme without posting anything still reaches
        // the picture: the settings pane is cheap and never shows a stale card.
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let next = HostTheme.read()
        guard next != current else { return }
        current = next
    }
}
