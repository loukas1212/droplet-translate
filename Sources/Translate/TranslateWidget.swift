import DroppyKit
import SwiftUI

struct TranslateWidget: View {
    @ObservedObject var model: TranslateModel
    let context: ShelfWidgetContext
    let openSettings: () -> Void
    private static let bodyFont = Font.system(size: 13)

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header
            languageRow
            tiles.frame(maxHeight: .infinity)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .translationRunner(model)
        .onChange(of: model.input) { model.inputChanged() }
        .onDisappear { model.shelfDidDisappear() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            title
            Spacer(minLength: DroppySpacing.md)
            translateButton(diameter: context.isCompact ? 28 : 34)
        }
    }

    private var title: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "translate").font(.system(size: 12, weight: .medium))
            Text(L10n.tr("title")).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    private func translateButton(diameter: CGFloat) -> some View {
        Button { model.translate() } label: {
            if model.status == .translating {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(TranslateCircleStyle(diameter: diameter, accent: .blue))
        .a11y("a11y.translate")
    }

    // MARK: Languages

    private var languageRow: some View {
        HStack(spacing: DroppySpacing.xsm) {
            languageMenu(selection: $model.sourceID, includesAuto: true, label: sourceLabel)
            iconButton("arrow.left.arrow.right", label: "a11y.swap", diameter: 24) { model.swapLanguages() }
                .disabled(!model.canSwap)
            languageMenu(selection: $model.targetID, includesAuto: false, label: model.name(for: model.targetID))
            if !context.isCompact {
                Spacer(minLength: DroppySpacing.md)
                pillButton("doc.on.clipboard", text: "paste", a11y: "a11y.paste") { model.pasteInput() }
                pillButton("arrow.up.page.on.clipboard", text: "copy", a11y: "a11y.copy", disabled: model.output.isEmpty) { model.copyOutput() }
                iconButton("speaker.wave.2.bubble.fill", label: "a11y.speak", diameter: 24) { model.toggleSpeech() }
                    .disabled(model.output.isEmpty)
            }
        }
        .frame(height: 28)
    }

    private var sourceLabel: String {
        guard model.sourceID == TranslateModel.auto else { return model.name(for: model.sourceID) }
        guard let detected = model.detected else { return L10n.tr("auto") }
        return String(format: L10n.tr("detected"), model.name(for: detected))
    }

    private func languageMenu(selection: Binding<String>, includesAuto: Bool, label: String) -> some View {
        Menu {
            if includesAuto {
                Button(L10n.tr("auto")) { selection.wrappedValue = TranslateModel.auto }
                Divider()
            }
            ForEach(model.languages) { language in
                Button(language.name) { selection.wrappedValue = language.id }
            }
        } label: {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(TranslatePillStyle(height: 28))
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        diameter: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(TranslateCircleStyle(diameter: diameter))
            .a11y(label)
    }

    private func pillButton(
        _ symbol: String,
        text: String,
        a11y: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(L10n.tr(text))
            }
        }
        .buttonStyle(TranslatePillStyle(height: 24))
        .a11y(a11y)
        .disabled(disabled)
    }

    // MARK: Text

    @ViewBuilder
    private var tiles: some View {
        if context.isCompact {
            VStack(spacing: DroppySpacing.xsm) { inputTile; outputTile }
        } else {
            HStack(spacing: DroppySpacing.sm) { inputTile; outputTile }
        }
    }

    private var inputTile: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.input)
                .font(Self.bodyFont)
                .scrollContentBackground(.hidden)
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                // Return translates, Shift-Return adds a line.
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    model.translate()
                    return .handled
                }
            if model.input.isEmpty {
                Text(L10n.tr("placeholder"))
                    .font(Self.bodyFont)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .padding(.leading, 5)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .padding(DroppySpacing.xsm)
        .tile()
    }

    private var outputTile: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                if model.status == .needsDownload {
                    Button(L10n.tr("status.download")) { openSettings() }
                        .buttonStyle(TranslatePillStyle(height: 24))
                }
            } else if model.output.isEmpty {
                Text(L10n.tr("output.placeholder"))
                    .font(Self.bodyFont)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            } else {
                ScrollView {
                    Text(model.output)
                        .font(Self.bodyFont)
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DroppySpacing.sm)
        .tile()
    }

    /// Messages shown in place of the translation. `.sameLanguage` keeps the
    /// text in the output, so it is a note, not a replacement.
    private var statusMessage: String? {
        let key: String?
        switch model.status {
        case .needsDownload: key = "needsDownload"
        case .unsupported: key = "unsupported"
        case .undetected: key = "undetected"
        case .failed: key = "failed"
        case .osTooOld: key = "old"
        case .sameLanguage: key = "same"
        case .idle, .translating: key = nil
        }
        return key.map { L10n.tr("status.\($0)") }
    }
}

private extension View {
    func a11y(_ key: String) -> some View {
        help(L10n.tr(key)).accessibilityLabel(L10n.tr(key))
    }
    /// A raised surface inside the widget. Not a frame around it: the root
    /// of the widget stays bare on the shelf's black.
    func tile() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(AdaptiveColors.notchSurfaceCardFill)
            )
    }
}
