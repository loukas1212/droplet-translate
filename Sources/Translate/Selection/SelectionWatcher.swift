import AppKit

@MainActor
final class SelectionWatcher {
    private var globalMonitor: Any?
    private var downPoint: NSPoint = .zero
    private var onText: ((SelectedTextService.SelectionCapture?) -> Void)?
    private var onCancel: (() -> Void)?
    private var sourcePID: pid_t?
    private var log: ((String) -> Void)?
    private var selectionAtMouseDown: SelectedTextService.SelectionCapture?
    private var readID = UUID()
    private var mouseIsDown = false

    var isMouseDown: Bool { mouseIsDown }

    @discardableResult
    func start(
        sourcePID: pid_t,
        log: @escaping (String) -> Void,
        onText: @escaping (SelectedTextService.SelectionCapture?) -> Void,
        onCancel: @escaping () -> Void
    ) -> Bool {
        stop()
        self.sourcePID = sourcePID
        self.log = log
        self.onText = onText
        self.onCancel = onCancel
        log("Select: drag watcher armed for pid=\(sourcePID)")
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { [weak self] event in
            let type = event.type
            let clickCount = event.clickCount
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handle(type: type, clickCount: clickCount, location: location)
            }
        }
        guard globalMonitor != nil else {
            log("Select: global mouse monitor unavailable")
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        onText = nil
        onCancel = nil
        sourcePID = nil
        log = nil
        selectionAtMouseDown = nil
        downPoint = .zero
        mouseIsDown = false
        readID = UUID()
    }

    private func handle(type: NSEvent.EventType, clickCount: Int, location: NSPoint) {
        switch type {
        case .leftMouseDown:
            readID = UUID()
            downPoint = location
            mouseIsDown = true
            selectionAtMouseDown = sourcePID.flatMap {
                SelectedTextService.captureSelection(inApplicationPID: $0)
            }
        case .leftMouseUp:
            let dragged = hypot(location.x - downPoint.x, location.y - downPoint.y) > 3
            let multiClick = clickCount >= 2      // Double/triple-click selects a word/line.
            downPoint = .zero
            mouseIsDown = false
            guard dragged || multiClick else {
                let callback = onCancel
                stop()
                callback?()
                return
            }
            log?("Select: mouse-up drag=\(dragged) multiClick=\(multiClick); reading pid=\(sourcePID.map(String.init) ?? "none")")
            let previousSelection = selectionAtMouseDown
            selectionAtMouseDown = nil
            readID = UUID()
            readWithRetry(attempts: 12, delay: 0.12, previousSelection: previousSelection, readID: readID)
        default:
            break
        }
    }

    // AX อาจอัปเดตช้ากว่าเมาส์ปล่อย จึงอ่านซ้ำสั้น ๆ
    private func readWithRetry(
        attempts: Int,
        delay: TimeInterval,
        previousSelection: SelectedTextService.SelectionCapture?,
        readID: UUID
    ) {
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.readWithRetry(
                    attempts: attempts,
                    delay: 0,
                    previousSelection: previousSelection,
                    readID: readID
                )
            }
            return
        }
        guard onText != nil, self.readID == readID else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let sourcePID else {
            log?("Select: no source PID for drag read")
            return
        }
        let capture = SelectedTextService.captureSelection(
            inApplicationPID: sourcePID,
            log: { [weak self] in self?.log?($0) }
        )
        let text = capture?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let elapsedMS = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
        if !text.isEmpty, let capture,
           previousSelection?.matchesSelection(capture) != true {
            log?("Select: drag read captured chars=\(text.count) after \(elapsedMS)ms")
            let callback = onText
            stop()
            callback?(capture)
        } else if attempts > 1 {
            let reason = capture == nil || text.isEmpty ? "empty" : "unchanged"
            log?("Select: drag read \(reason), retries left=\(attempts - 1), elapsed=\(elapsedMS)ms")
            readWithRetry(
                attempts: attempts - 1,
                delay: 0.1,
                previousSelection: previousSelection,
                readID: readID
            )
        } else {
            let reason = capture == nil || text.isEmpty ? "no AX text" : "selection unchanged"
            log?("Select: drag read exhausted, \(reason) (elapsed=\(elapsedMS)ms)")
            let callback = onText
            stop()
            callback?(nil)
        }
    }
}
