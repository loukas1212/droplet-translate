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
    /// What the host spends above and below the widget's rectangle: the notch
    /// corner inset, or 0 on a solo island card. The descriptor includes it.
    var shelfHeightBudget: CGFloat = SidePanelContentView.shelfContentInsetBudget
    /// Asks the host for a card height. The content reports the rectangle it
    /// needs; the widget adds the host's inset budget.
    var onShelfHeight: (CGFloat) -> Void = { _ in }
    @State private var chip = SidePanelChipState()

    var body: some View {
        GeometryReader { proxy in
            SidePanelContentView(
                model: model,
                chip: chip,
                requestCapture: requestCapture,
                requestSelection: requestSelection,
                cancelSelection: cancelSelection,
                boxFloor: SidePanelContentView.shelfBoxFloor,
                boxCap: SidePanelContentView.shelfBoxCap,
                keepsGripInsideCard: true,
                maxBodyHeight: proxy.size.height,
                rowWidth: min(rowWidth, proxy.size.width),
                mountWidth: proxy.size.width,
                onShelfGripTap: {
                    guard model.canTranslate else { return }
                    model.translate()
                },
                onSubmit: translateFromShelf,
                onClear: {
                    model.clearInput()
                },
                onClose: {
                    model.hideShelf()
                },
                onShelfContentHeight: { height in
                    onShelfHeight(height + shelfHeightBudget)
                }
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .translationRunner(model)
        .onChange(of: model.input) { _, _ in
            model.inputChanged()
        }
        .onAppear {
            model.shelfDidAppear()
        }
        .onDisappear {
            model.shelfDidDisappear()
        }
    }

    /// Return translates the text.
    private func translateFromShelf() {
        guard model.canTranslate else { return }
        model.translate()
    }
}
