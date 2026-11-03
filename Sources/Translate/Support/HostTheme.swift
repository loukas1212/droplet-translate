import AppKit
import Combine
import Foundation

/// The surface theme the user picked in Droppy for the shelf and the
/// droplet's own panels.
///
/// DroppyKit draws the host's surfaces in the theme but does not publish which
/// one is on — `surfaceAppearance` is only dark or light — so the droplet reads
/// the host's own setting. Droppy keeps one theme for the notch surface and one
/// for the shelf and floating surfaces. This droplet draws only the second
/// kind; the host draws the notch. Reading the notch key here made the preview
/// follow the notch while the shelf stayed on its own theme.
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

/// Redraws the card when the host's theme changes, so a theme picked in Droppy
/// reaches a card that is already on screen. The host's own notification is
/// the first signal; the defaults and a slow poll catch a host that writes the
/// preference without announcing it.
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
