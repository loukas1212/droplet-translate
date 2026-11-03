import DroppyKit
import SwiftUI

/// The controls the edge panel's sliding chip can mark.
enum SidePanelChipTarget: Hashable, CaseIterable {
    case source, target, resultTarget, swap, more, engine
    /// The discs inside the boxes: copy and paste, plus the download pill in
    /// the result's empty state.
    case download, copy, paste
    /// The footer's trash, beside the more disc.
    case clear
    /// The result page's close, in its row above the box.
    case close
    /// The rows of the open more menu. The panel's chip marks the row itself.
    case menuCapture, menuSelect, menuPin, menuSettings
    /// The two boxes. Their frames contain the discs above, so they are tested
    /// last, and the chip takes the box's own silhouette.
    case input, result
}

extension SidePanelChipTarget {
    /// A box's mark takes the box's own silhouette, not a capsule.
    var isBox: Bool { self == .input || self == .result }

    /// A control of the language row, which the result page fades out. Its frame stays
    /// in the preference after the fade, so the hit test must skip it by hand.
    var isHeader: Bool {
        switch self {
        case .source, .target, .swap: return true
        default: return false
        }
    }

    /// A row of the open more menu.
    var isMenu: Bool {
        switch self {
        case .menuCapture, .menuSelect, .menuPin, .menuSettings: return true
        default: return false
        }
    }

    /// A button: every target but the two boxes, including the rows of the open
    /// more menu. A button keeps its own glass and its own ink, so the chip only
    /// lights its silhouette and never draws a second control over it.
    var isControl: Bool { !isBox }
}

/// The chip's shared state: the control under the pointer, whether it is held
/// down, and where every control sits.
///
/// One mark slides over the whole panel to the control under the pointer. On
/// macOS 26 it is a capsule of real Liquid Glass; before that it is a light in
/// the control's own silhouette. Every control keeps its glass and its ink, so
/// the mark never draws a second control over the first.
@MainActor
final class SidePanelChipState: ObservableObject {
    /// The control under the pointer; nil hides the mark.
    @Published var target: SidePanelChipTarget? {
        didSet {
            guard let target else { return }
            lastTarget = target
        }
    }
    /// The last control the chip marked, so it can fade over that frame and
    /// keep its corner after the pointer leaves.
    @Published private(set) var lastTarget: SidePanelChipTarget?
    /// True while the pointer holds the marked control.
    @Published var pressed = false
    /// Each control's frame, in the panel's coordinate space.
    @Published var frames: [SidePanelChipTarget: CGRect] = [:]

    /// The space the frames are measured in.
    static let space = "sidePanelChip"

    /// The frame the chip marks a control at, published by the control itself.
    func chipRect(for target: SidePanelChipTarget) -> CGRect? {
        frames[target]
    }

    /// True where the platform draws Liquid Glass, so the mark can be a glass
    /// capsule that slides instead of a hand-drawn light.
    static var hasLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// The mark's slide: the kit's tab spring with a little more travel, so the
    /// arrival settles instead of stopping. Reduce Motion keeps the kit's ease.
    static func slide(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? DroppyAnimation.tabSelect
            : .spring(response: 0.33, dampingFraction: 0.75, blendDuration: 0)
    }

    /// The faint light the mark lays over the control where there is no Liquid
    /// Glass. A box takes a neutral wash instead: its words sit on the text
    /// itself, and the accent would tint them.
    func markFill(for target: SidePanelChipTarget?) -> Color {
        guard target?.isControl == true else { return AdaptiveColors.overlayAuto(0.17) }
        return AdaptiveColors.selectionBlueAuto.opacity(pressed ? 0.16 : 0.10)
    }

    /// The light that spills past the control's rim where there is no Liquid
    /// Glass. Boxes take none, since the glow would reach their words.
    func markGlow(for target: SidePanelChipTarget?) -> Color {
        guard target?.isControl == true else { return .clear }
        return AdaptiveColors.selectionBlueAuto.opacity(pressed ? 0.55 : 0.40)
    }

    /// The glowing ring's width and blur. The spill reaches about 3pt past the
    /// rim, inside the air every control keeps from the card's edge.
    static let markGlowWidth: CGFloat = 1.5
    static let markGlowRadius: CGFloat = 2.5

    /// The frame the mark takes: the marked control's, or the one it last
    /// covered. The mark travels between the two, so it slides from control to
    /// control instead of blinking at each one.
    func rect(resting: CGRect?) -> CGRect? {
        if let target { return chipRect(for: target) ?? resting }
        if let lastTarget, let rect = chipRect(for: lastTarget) { return rect }
        return resting
    }
}

/// The mark on macOS 26: one capsule of Liquid Glass in the control's own
/// frame. It sits above the controls, so the control's own glass stays
/// underneath and the chip redraws the control's ink above the glass.
struct SidePanelChipGlass: View {
    /// The marked control's frame, in the chip's space.
    var rect: CGRect

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .frame(width: rect.width, height: rect.height)
                // The theme's highlight washes the glass, so the mark reads
                // brighter than the control's own glass under it.
                .glassEffect(
                    .regular.tint(AdaptiveColors.selectionBlueAuto.opacity(0.18)),
                    in: Capsule(style: .continuous)
                )
                .offset(x: rect.minX, y: rect.minY)
        }
    }
}

/// Where the controls the chip can mark sit, published by the controls
/// themselves.
struct SidePanelChipFrameKey: PreferenceKey {
    static var defaultValue: [SidePanelChipTarget: CGRect] { [:] }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Reports where a marked control sits, so the chip can mark it. `inset`
    /// pulls the mark inside the control's rim, as the boxes' hover chrome is.
    func chipTarget(_ target: SidePanelChipTarget?, inset: CGFloat = 0) -> some View {
        chipTarget(
            target,
            insets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)
        )
    }

    /// The same, with each side pulled in by its own amount: the language row's
    /// halves keep 3pt on the capsule's end and run to the pocket's tangent,
    /// where the pocket's curve leaves the same 3pt.
    func chipTarget(_ target: SidePanelChipTarget?, insets: EdgeInsets) -> some View {
        background {
            GeometryReader { proxy in
                let rect = proxy.frame(in: .named(SidePanelChipState.space))
                let marked = CGRect(
                    x: rect.minX + insets.leading,
                    y: rect.minY + insets.top,
                    width: max(0, rect.width - insets.leading - insets.trailing),
                    height: max(0, rect.height - insets.top - insets.bottom)
                )
                Color.clear.preference(
                    key: SidePanelChipFrameKey.self,
                    value: target.map { [$0: marked] } ?? [:]
                )
            }
        }
    }
}

/// The chip's state, for the controls that share it.
private struct SidePanelChipKey: EnvironmentKey {
    static var defaultValue: SidePanelChipState? { nil }
}

extension EnvironmentValues {
    /// The panel's chip; nil where the panel does not draw one.
    var sidePanelChip: SidePanelChipState? {
        get { self[SidePanelChipKey.self] }
        set { self[SidePanelChipKey.self] = newValue }
    }
}
