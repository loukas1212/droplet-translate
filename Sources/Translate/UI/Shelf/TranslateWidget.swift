import DroppyKit
import SwiftUI

/// The shelf draws the edge panel's card inside the host's slot: the same
/// language row, input, result and footer, without the panel's own window.
struct TranslateWidget: View {
    @ObservedObject var model: TranslateModel

    var requestCapture: () -> Void = {}
    var requestSelection: () -> Void = {}
    var cancelSelection: () -> Void = {}
    /// The grouped shelf slot is 230pt wide; the language row shrinks with it.
    var rowWidth = SidePanelContentView.defaultRowWidth
    /// The card height step the capsule is on.
    var shelfStep: ShelfHeightStep = .compact
    /// The card's padding above and below the widget's rectangle. The host
    /// spends it before this view is laid out, and it differs by surface, so
    /// the growth below is measured against the rectangle this view gets.
    var hostInset: CGFloat = 16
    /// Asks the host for a card height.
    var onShelfStep: (ShelfHeightStep) -> Void = { _ in }
    /// The step the tap last asked for. The host resizes the card on its own
    /// schedule, so the content cannot wait for a new context to change.
    @State private var step: ShelfHeightStep?
    @State private var chip = SidePanelChipState()

    private var currentStep: ShelfHeightStep { step ?? shelfStep }

    var body: some View {
        GeometryReader { proxy in
            // Fill the card the host hands over. A notch card spends 16pt of
            // its height on the corner inset; a solo island card spends none,
            // so the extra becomes box room and the footer stays on the bottom
            // edge in both.
            let height = proxy.size.height
            // The boxes ride the card the host is drawing, so the host's
            // spring is the only clock a resize runs on.
            let growth = ShelfHeightStep.growth(forHeight: height, hostInset: hostInset)
            SidePanelContentView(
                model: model,
                chip: chip,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                keepsGripInsideCard: true,
                maxBodyHeight: height,
                rowWidth: min(rowWidth, proxy.size.width),
                shelfStep: currentStep.rawValue,
                shelfGrowth: growth,
                onShelfGripTap: {
                    guard currentStep == .compact, model.canTranslate else { return }
                    model.translate()
                    advance(to: .medium)
                },
                onShelfGripDrag: { direction in
                    guard let next = currentStep.dragged(
                        direction,
                        canTranslate: model.canTranslate
                    ) else { return }
                    advance(to: next)
                },
                onSubmit: translateFromShelf
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .translationRunner(model)
        .onChange(of: model.input) { _, text in
            model.inputChanged()
            // An empty box has nothing to read, so the card returns to the
            // height it opens at, as the trash does in the panel.
            if text.isEmpty, currentStep != .compact {
                advance(to: .compact)
            }
        }
        .onAppear {
            model.shelfDidAppear()
            _ = model.takePageRequest()
        }
        .onDisappear {
            model.shelfDidDisappear()
        }
    }

    /// Return translates the text. The opening card has no result box, so the
    /// card rises to the second step the moment the run starts.
    private func translateFromShelf() {
        guard model.canTranslate else { return }
        model.translate()
        guard currentStep == .compact else { return }
        advance(to: .medium)
    }

    /// Steps the card. The host owns the card height and animates it on its
    /// own spring, so a phase moves one thing at a time: first the boxes fold
    /// back to the two-box layout, then the host shrinks the card and the
    /// boxes ride that height down. Running both springs at once read as two
    /// layouts sliding through each other.
    private func advance(to next: ShelfHeightStep) {
        // An empty box is the trash or a delete that took the last character:
        // the result leaves in this same update. Let that land before the
        // card moves, or the shrink plays over a box that is still changing
        // and reads as a jump next to the same shrink after a delete.
        let from = currentStep
        if next == .compact, from != .compact, !model.canTranslate {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                guard currentStep == from, model.input.isEmpty else { return }
                collapse(to: next)
            }
            return
        }
        collapse(to: next)
    }

    private func collapse(to next: ShelfHeightStep) {
        // The fold buys the result box time to shrink before the height moves.
        // An empty box has no result to fold, so the card can drop in one
        // spring instead.
        if currentStep == .full, next == .compact, model.canTranslate {
            withAnimation(DroppyAnimation.state) { step = .medium }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(280))
                // Typing in the folded card cancels the shrink: the new text
                // has already given the card a reason to stay open.
                guard currentStep == .medium, !model.canTranslate else { return }
                step = .compact
                onShelfStep(.compact)
            }
            return
        }
        if next.rawValue > currentStep.rawValue {
            withAnimation(DroppyAnimation.notchOpen) { step = next }
        } else {
            step = next
        }
        onShelfStep(next)
    }
}

/// The three heights the shelf's capsule cycles through. The host owns the
/// card, so a tap asks for the next height instead of dragging the edge.
@MainActor
enum ShelfHeightStep: Int, CaseIterable {
    case compact, medium, full

    /// The input at its tallest, then the input over the full result box, then
    /// the result on the whole face. The last two share a height; the third
    /// spends the language row on the result.
    var room: CGFloat {
        switch self {
        case .compact: SidePanelContentView.maxBoxHeight
        case .medium: SidePanelContentView.shelfResultRoom
        case .full: SidePanelContentView.shelfFullRoom
        }
    }

    var showsHeader: Bool { self != .full }

    /// The card's content without the host's corner inset.
    var contentHeight: CGFloat {
        SidePanelContentView.shelfContentHeight(forRoom: room, showsHeader: showsHeader)
    }

    var height: CGFloat {
        SidePanelContentView.shelfCardHeight(forRoom: room, showsHeader: showsHeader)
    }

    var next: ShelfHeightStep {
        Self(rawValue: (rawValue + 1) % Self.allCases.count) ?? .compact
    }

    /// How far the card has grown from the opening height to the result's
    /// height, 0…1, measured from `height` with the host's padding removed.
    /// The interval is the same on both shapes; `hostInset` only shifts it.
    static func growth(forHeight height: CGFloat, hostInset: CGFloat) -> CGFloat {
        let from = compact.height - hostInset
        let to = medium.height - hostInset
        guard to > from else { return 0 }
        return min(max((height - from) / (to - from), 0), 1)
    }
}

extension ShelfHeightStep {
    /// The step below this one; the opening card has no lower step.
    var previous: ShelfHeightStep {
        Self(rawValue: (rawValue + Self.allCases.count - 1) % Self.allCases.count) ?? .compact
    }

    /// The step a drag on the shelf's handle asks for, or nil when the card
    /// cannot move that way. Pulling down grows the card, but an empty box has
    /// nothing to show, so it stays at the opening height; pulling up always
    /// shrinks.
    func dragged(_ direction: ShelfGripDrag, canTranslate: Bool) -> ShelfHeightStep? {
        switch direction {
        case .down:
            guard canTranslate, self != .full else { return nil }
            return next
        case .up:
            return self == .compact ? nil : previous
        }
    }
}
