import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DroppyKit
import Foundation

@MainActor
final class ClipboardFallback {
    private struct ItemSnapshot {
        let values: [(NSPasteboard.PasteboardType, Data)]
    }

    private let pasteboard = NSPasteboard.general

    func readSelection(host: DropletHost) async -> String? {
        guard host.isGranted(.accessibility), host.isGranted(.clipboardRead),
              host.isGranted(.clipboardWrite), AXIsProcessTrusted(),
              !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false) else { return nil }

        let originalItems = pasteboard.pasteboardItems ?? []
        let snapshots = originalItems.map { item in
            ItemSnapshot(values: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
        guard zip(originalItems, snapshots).allSatisfy({ item, snapshot in
            item.types.count == snapshot.values.count
        }) else { return nil }
        let initialChangeCount = pasteboard.changeCount
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        var copiedChangeCount: Int?
        defer {
            if let copiedChangeCount, pasteboard.changeCount == copiedChangeCount {
                pasteboard.clearContents()
                let restored = snapshots.compactMap { snapshot -> NSPasteboardItem? in
                    let item = NSPasteboardItem()
                    for (type, data) in snapshot.values { item.setData(data, forType: type) }
                    return snapshot.values.isEmpty ? nil : item
                }
                if !restored.isEmpty { pasteboard.writeObjects(restored) }
            }
        }

        let deadline = ContinuousClock.now + .milliseconds(350)
        while ContinuousClock.now < deadline, !Task.isCancelled,
              host.isGranted(.accessibility), host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite) {
            try? await Task.sleep(for: .milliseconds(20))
            let changeCount = pasteboard.changeCount
            guard changeCount != initialChangeCount else { continue }
            if copiedChangeCount == nil { copiedChangeCount = changeCount }
            guard let text = pasteboard.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return text
        }
        return nil
    }
}
