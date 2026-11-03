import DroppyKit
import Foundation

/// Where a finished translation is shown. The chosen mode is the only one that
/// presents a result or a status; the other surfaces stay out of the way.
enum ResultDisplay: String, CaseIterable, Identifiable, Sendable {
    /// The result lands in the shelf widget, which reopens after a capture or
    /// selection so the result is not lost.
    case normal
    /// A floating panel next to the captured region; the shelf stays put.
    case panel
    /// The droplet's own edge panel opens with the result in it.
    case sidePanel

    var id: String { rawValue }
}

/// The page a card shows: input, result, pair or status.
enum Page: String, CaseIterable, Identifiable, Sendable {
    /// Paste or type; no translation yet.
    case input
    /// The translation alone.
    case result
    /// The original above the translation, for a result that needs its context.
    case pair
    /// Loading, error or notice.
    case status

    var id: String { rawValue }

    /// The pages the setting can choose: input and status come from the state.
    static let chosen: [Page] = [.result, .pair]

    /// The card shows the original above the translation only on the pair page.
    var showsOriginal: Bool { self == .pair }
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

