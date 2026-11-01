import AppKit
import SwiftUI

private struct RegionPickerView: View {
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var startPoint: CGPoint = .zero
    @State private var currentPoint: CGPoint = .zero
    @State private var isDragging = false
    @State private var didComplete = false

    private func finish(_ rect: CGRect?) {
        guard !didComplete else { return }
        didComplete = true
        if let rect {
            onComplete(rect)
        } else {
            onCancel()
        }
    }

    private var selectionRect: CGRect {
        guard isDragging else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            if isDragging && selectionRect.width > 10 && selectionRect.height > 10 {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
                    .blendMode(.destinationOut)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .shadow(color: .white.opacity(0.9), radius: 2)
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .position(x: selectionRect.midX, y: selectionRect.midY)
            }
        }
        .compositingGroup()
        .onExitCommand { finish(nil) }
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isDragging { finish(nil) }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .onChanged { value in
                    if !isDragging {
                        startPoint = value.startLocation
                        isDragging = true
                    }
                    currentPoint = value.location
                }
                .onEnded { _ in
                    let rect = selectionRect
                    isDragging = false
                    if rect.width > 10 && rect.height > 10 {
                        finish(rect)
                    } else {
                        finish(nil)
                    }
                }
        )
    }
}

/// Droppy runs in the background, so the first press on a window it opens is
/// usually the one that activates the app. Without this, that press only
/// brings Droppy forward and the drag that should start the selection is lost.
private final class RegionPickerHostingView: NSHostingView<RegionPickerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class RegionOverlayWindow: NSWindow {
    private static weak var activeWindow: RegionOverlayWindow?
    private var completion: ((CGRect?) -> Void)?
    private var escapeMonitor: Any?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        // Above every window the host draws, including the shelf panel. The
        // card is still animating out when the picker appears, and a picker
        // under it would swallow the first click and show the fading card
        // as a dark patch over the dim.
        let hostTop = NSApp.windows
            .filter { $0 !== self }
            .map(\.level.rawValue)
            .max() ?? Int(NSWindow.Level.statusBar.rawValue)
        level = NSWindow.Level(rawValue: max(hostTop + 1, NSWindow.Level.statusBar.rawValue + 1))
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            finish(rect: nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        finish(rect: nil)
    }

    private func finish(rect: CGRect?) {
        guard let handler = completion else { return }
        Self.activeWindow = nil
        completion = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        orderOut(nil)
        handler(rect)
    }

    static func cancelActive() { activeWindow?.finish(rect: nil) }

    static func pickRegion() async -> (rect: CGRect, screen: NSScreen)? {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let rect: CGRect? = await withCheckedContinuation { continuation in
            let window = RegionOverlayWindow(screen: screen)
            activeWindow = window
            window.setFrame(screen.frame, display: true)

            var resumed = false
            func resume(_ result: CGRect?) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: result)
            }
            window.completion = { rect in
                resume(rect)
            }

            window.contentView = RegionPickerHostingView(rootView: RegionPickerView(
                onComplete: { [weak window] rect in
                    guard let window else { resume(nil); return }
                    window.finish(rect: rect)
                },
                onCancel: { [weak window] in
                    guard let window else { resume(nil); return }
                    window.finish(rect: nil)
                }
            ))
            window.escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
                guard event.keyCode == 53,
                      let window,
                      event.windowNumber == window.windowNumber else { return event }
                window.finish(rect: nil)
                return nil
            }
            window.makeKeyAndOrderFront(nil)
        }

        guard let rect else { return nil }
        return (rect, screen)
    }
}
