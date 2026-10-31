import DroppyKit
import Foundation

/// Where a finished translation is shown. A setting, not a behaviour switch:
/// the same result goes to the widget, a floating panel or the edge panel.
enum ResultDisplay: String, CaseIterable, Identifiable, Sendable {
    /// The shelf reopens after a capture or selection, so the result is not lost.
    case normal
    /// A floating panel next to the captured region; the shelf stays put.
    case panel
    /// The droplet's own edge panel opens with the result in it.
    case sidePanel

    var id: String { rawValue }
}

enum ResultContent: String, CaseIterable, Identifiable, Sendable {
    case result
    /// The original above the translation, for a result that needs its context.
    case both

    var id: String { rawValue }
}

/// The screen edge the side panel docks to.
enum SidePanelSide: String, CaseIterable, Identifiable, Sendable {
    case right
    case left

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        }
    }
}

extension ResultContent {
    /// The panel shows the original above the translation only when the
    /// setting asks for it.
    var showsOriginal: Bool { self == .both }
}
