import AppKit
import Combine
import Foundation

/// The surface theme the user picked in Droppy for the display the panel is on.
///
/// DroppyKit draws the host's surfaces in the theme but does not publish which
/// one is on — `surfaceAppearance` is only dark or light — so the panel reads
/// the host's own setting. Droppy keeps one setting per display kind: a screen
/// with a camera housing uses `notchedSurfaceAppearance`, every other screen
/// uses `externalSurfaceAppearance`. The panel is docked to one screen, so the
/// key follows that screen's kind. A missing key falls back to the other one,
/// then to Dynamic Glass, Droppy's default.
enum HostTheme: String, Equatable {
    case black
    case liquidGlass
    case dynamicGlass

    static func read(
        from defaults: UserDefaults = .standard,
        notched: Bool = NSScreen.main?.auxiliaryTopLeftArea != nil
    ) -> HostTheme {
        let own = notched ? "notchedSurfaceAppearance" : "externalSurfaceAppearance"
        let other = notched ? "externalSurfaceAppearance" : "notchedSurfaceAppearance"
        let raw = defaults.string(forKey: own) ?? defaults.string(forKey: other)
        return raw.flatMap(HostTheme.init(rawValue:)) ?? .dynamicGlass
    }
}

/// Redraws the card when the host's defaults change, so a theme picked in
/// Droppy reaches a card that is already on screen. `current` still reads the
/// value fresh, so folding and reopening the card also picks up a change made
/// outside this process.
final class HostThemeStore: ObservableObject {
    /// Bumped on every defaults change; the card observes it to redraw.
    @Published private(set) var revision = 0
    private var cancellable: AnyCancellable?

    var current: HostTheme { HostTheme.read() }

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.revision += 1 }
    }
}
