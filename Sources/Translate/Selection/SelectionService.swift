import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DroppyKit

@MainActor
final class SelectionService {
    private var host: DropletHost?
    private weak var model: TranslateModel?
    private let watcher = SelectionWatcher()
    private var axObserver: AXObserver?
    private var observedApplication: AXUIElement?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?
    private var sourcePID: pid_t?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var selectedTextBeforeClick: (capture: SelectedTextService.SelectionCapture, pid: pid_t)?
    /// The element a refresh reads directly, avoiding another tree walk.
    private var snapshotElement: AXUIElement?
    private var consumedSelection: SelectedTextService.SelectionCapture?
    private var selectionTimer: Timer?
    private var escapeMonitor: Any?
    private var interactionID = UUID()
    private var interactionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var selectionContinuation: CheckedContinuation<Bool, Never>?
    private var selectionFailure: String?

    private static func shouldUsePreselectedSelection(
        hasText: Bool,
        matchesSource: Bool,
        alreadyConsumed: Bool
    ) -> Bool {
        hasText && matchesSource && !alreadyConsumed
    }

    static func checkPreselectedSelectionRules() {
        assert(shouldUsePreselectedSelection(hasText: true, matchesSource: true, alreadyConsumed: false))
        assert(!shouldUsePreselectedSelection(hasText: true, matchesSource: true, alreadyConsumed: true))
        assert(!shouldUsePreselectedSelection(hasText: true, matchesSource: false, alreadyConsumed: false))
        assert(!shouldUsePreselectedSelection(hasText: false, matchesSource: true, alreadyConsumed: false))
    }

    func attach(host: DropletHost, model: TranslateModel) {
        Self.checkPreselectedSelectionRules()
        self.host = host
        self.model = model
        if host.isGranted(.accessibility) {
            workspaceObservers.append(
                NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                    Task { @MainActor in self?.rememberSourceApplication(app) }
                }
            )
            startSelectionObserver()
        }
    }

    func detach() {
        interactionID = UUID()
        interactionTask?.cancel()
        interactionTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        finishSelection(returning: false)
        permissionTask?.cancel()
        permissionTask = nil
        stopEscapeMonitor()
        watcher.stop()
        selectionTimer?.invalidate()
        selectionTimer = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        sourcePID = nil
        stopAXObserver()
        selectedTextBeforeClick = nil
        snapshotElement = nil
        consumedSelection = nil
        host = nil
        model = nil
    }

    func requestSelection() {
        guard let host, let model, model.selectState == .idle else { return }
        guard hasAccessibilityPermission else {
            requestAccessibilityPermission(host: host, model: model)
            return
        }
        let processID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let selectionPID = frontmostPID.flatMap { $0 == processID ? nil : $0 }
            ?? selectedTextBeforeClick?.pid
            ?? sourcePID
        if frontmostPID == processID, let preselection = selectedTextBeforeClick {
            if !isAlreadyConsumed(preselection.capture) {
                requestSelection(from: preselection.pid)
                return
            }
            model.showNotice(L10n.tr("select.readFailed"))
            return
        }
        requestSelection(from: selectionPID)
    }

    private func requestSelection(from selectionPID: pid_t?) {
        guard let host, let model, model.selectState == .idle else { return }
        guard hasAccessibilityPermission else {
            if host.isGranted(.accessibility) {
                requestAccessibilityPermission(host: host, model: model)
            } else {
                model.showNotice(L10n.tr("permission.accessibility"))
            }
            return
        }
        stopEscapeMonitor()
        interactionID = UUID()
        let requestID = interactionID
        selectionFailure = nil
        let preselected = selectedTextBeforeClick
        let usablePreselection: SelectedTextService.SelectionCapture?
        if let preselected,
            Self.shouldUsePreselectedSelection(
                 hasText: !preselected.capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                 matchesSource: selectionPID.map { $0 == preselected.pid } ?? false,
                 alreadyConsumed: isAlreadyConsumed(preselected.capture)
            ) {
            host.log.info("Select: using tracked selection (\(preselected.capture.text.count) chars)")
            usablePreselection = preselected.capture
        } else {
            usablePreselection = nil
        }
        model.selectPulling()
        interactionTask?.cancel()
        interactionTask = Task { [weak self] in
            guard let self, let model = self.model else {
                return
            }
            if let usablePreselection {
                // Normal keeps the shelf open so the widget receives the
                // result; other destinations hide it as the slow path does.
                if model.resultDisplay == .normal {
                    self.consume(usablePreselection, model: model)
                    return
                }
                let hidden = await model.withShelfHidden {
                    guard !Task.isCancelled else { return false }
                    self.consume(usablePreselection, model: model)
                    model.revealAfterShelfHidden("translate")
                    return true
                }
                if !hidden { model.selectCancelled() }
                return
            }
            let result = await model.withShelfHidden {
                guard !Task.isCancelled, self.hasAccessibilityPermission else {
                    model.showNotice(L10n.tr("permission.accessibility"))
                    return false
                }
                guard let selectionPID else {
                    model.showNotice(L10n.tr("select.readFailed"))
                    return false
                }
                let sourceApp = NSRunningApplication(processIdentifier: selectionPID)
                _ = SelectedTextService.enableWebContentAccessibility(
                    inApplicationPID: selectionPID,
                    bundleIdentifier: sourceApp?.bundleIdentifier,
                    log: { host.log.info($0) }
                )
                if let selected = SelectedTextService.captureSelection(inApplicationPID: selectionPID,
                    log: { host.log.info($0) }), !selected.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.consume(selected, model: model)
                    model.revealAfterShelfHidden("translate")
                    return true
                }
                if host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite),
                   host.permissions.status(for: .accessibility) == .granted,
                   AXIsProcessTrusted() {
                    let copyPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    if let copyPID, copyPID != ProcessInfo.processInfo.processIdentifier,
                       let copied = await ClipboardFallback().readSelection(host: host),
                       self.hasAccessibilityPermission,
                       host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite) {
                        self.consumeText(copied, model: model, clearPID: copyPID)
                        model.revealAfterShelfHidden("translate")
                        return true
                    }
                } else if host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite) {
                    model.showNotice(L10n.tr("select.readFailed"))
                }
                self.watchForEscape(requestID: requestID)
                guard self.watcher.start(sourcePID: selectionPID, log: { host.log.info($0) }, onText: { [weak self] capture in
                    Task { @MainActor in
                        guard let self else { return }
                        if let capture {
                            self.consume(capture, model: model)
                            model.revealAfterShelfHidden("translate")
                            self.finishSelection(returning: true)
                        } else {
                            self.dragReadFailed(requestID: requestID)
                        }
                    }
                }, onCancel: { [weak self] in
                    Task { @MainActor in
                        guard let self, self.interactionID == requestID else { return }
                        self.selectionFailure = L10n.tr("select.readFailed")
                        self.finishSelection(returning: false)
                    }
                }) else {
                    model.showNotice(L10n.tr("select.readFailed"))
                    return false
                }
                model.selectArmed()
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled, let self, self.interactionID == requestID else { return }
                    self.selectionFailure = L10n.tr("select.timeout")
                    self.finishSelection(returning: false)
                }
                self.timeoutTask = timeoutTask
                let succeeded = await withCheckedContinuation { continuation in
                    self.selectionContinuation = continuation
                }
                self.stopEscapeMonitor()
                self.watcher.stop()
                timeoutTask.cancel()
                self.timeoutTask = nil
                guard succeeded, !Task.isCancelled else {
                    model.selectCancelled()
                    if let message = self.selectionFailure { model.showNotice(message) }
                    self.selectionFailure = nil
                    return false
                }
                guard self.hasAccessibilityPermission else {
                    model.showNotice(L10n.tr("permission.accessibility"))
                    model.selectCancelled()
                    return false
                }
                return true
            }
            if !result { model.selectCancelled() }
        }
    }

    private var hasAccessibilityPermission: Bool {
        guard let host else { return false }
        return host.isGranted(.accessibility)
            && host.permissions.status(for: .accessibility) == .granted
            && AXIsProcessTrusted()
    }

    private func consume(_ capture: SelectedTextService.SelectionCapture, model: TranslateModel) {
        ingest(capture, into: model)
    }

    private func consumeText(_ text: String, model: TranslateModel, clearPID: pid_t?) {
        selectedTextBeforeClick = nil
        if let clearPID {
            _ = SelectedTextService.clearSelection(
                inApplicationPID: clearPID,
                log: { [weak self] in self?.host?.log.info($0) }
            )
        }
        model.selectCancelled()
        model.ingestCaptured(text)
    }

    private func startSelectionObserver() {
        selectionTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollSelection() }
        }
        selectionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshObservedSelection()
    }

    /// The AX observer reports selection changes. This timer only catches a
    /// focus that moved, then re-reads the known element; round trips are costly.
    private func pollSelection() {
        guard let app = observedApplication else {
            refreshObservedSelection()
            return
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return }
        let element = focused as! AXUIElement
        if let snapshotElement, CFEqual(snapshotElement, element) {
            refreshSelectedText(from: element, application: app, shallow: true)
        } else {
            refreshFocusedElementSelection()
        }
    }

    private func refreshObservedSelection() {
        guard host?.isGranted(.accessibility) == true,
              host?.permissions.status(for: .accessibility) == .granted,
              AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else {
            selectedTextBeforeClick = nil
            snapshotElement = nil
            return
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        rememberSourceApplication(app)
        refreshFocusedElementSelection()
    }

    private func rememberSourceApplication(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        sourcePID = pid
        guard observedPID != pid else { return }

        stopAXObserver()
        selectedTextBeforeClick = nil
        snapshotElement = nil
        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let status = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let service = Unmanaged<SelectionService>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard service.host?.isGranted(.accessibility) == true,
                      service.host?.permissions.status(for: .accessibility) == .granted,
                      AXIsProcessTrusted() else {
                    service.stopAXObserver()
                    return
                }
                service.selectionChanged(element: element, notification: notification)
            }
        }, &observer)
        guard status == .success, let observer else {
            host?.log.info("Select: AX observer creation failed for pid=\(pid) (AX \(status.rawValue))")
            observedPID = nil
            return
        }
        observedPID = pid
        observedApplication = appElement
        axObserver = observer
        let focusStatus = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedUIElementChangedNotification as CFString,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        if focusStatus != .success {
            host?.log.info("Select: focused-element observer unavailable (AX \(focusStatus.rawValue))")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        host?.log.info("Select: source application pid=\(pid), name=\(app.localizedName ?? "unknown")")
    }

    private func selectionChanged(element: AXUIElement, notification: CFString) {
        if notification as String == kAXFocusedUIElementChangedNotification as String {
            if let observer = axObserver, let observedElement {
                _ = AXObserverRemoveNotification(
                    observer, observedElement, kAXSelectedTextChangedNotification as CFString
                )
            }
            observedElement = nil
            refreshFocusedElementSelection()
        } else {
            refreshSelectedText(from: element)
        }
    }

    private func refreshFocusedElementSelection() {
        guard let app = observedApplication else { return }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            selectedTextBeforeClick = nil
            return
        }
        let element = focused as! AXUIElement
        if let observer = axObserver,
           observedElement.map({ !CFEqual($0, element) }) ?? true {
            if let oldElement = observedElement {
                _ = AXObserverRemoveNotification(
                    observer, oldElement, kAXSelectedTextChangedNotification as CFString
                )
            }
            observedElement = element
            let selectionStatus = AXObserverAddNotification(
                observer,
                element,
                kAXSelectedTextChangedNotification as CFString,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            )
            if selectionStatus != .success {
                host?.log.info("Select: selected-text observer unavailable (AX \(selectionStatus.rawValue))")
            }
        }
        refreshSelectedText(from: element, application: app)
    }

    private func refreshSelectedText(
        from element: AXUIElement,
        application: AXUIElement? = nil,
        shallow: Bool = false
    ) {
        guard let observedPID else {
            selectedTextBeforeClick = nil
            snapshotElement = nil
            return
        }
        if shallow {
            let read = SelectedTextService.selectedTextRead(
                from: element,
                includeTextMarkerRange: true
            )
            if let text = read.text,
               let capture = SelectedTextService.capture(
                   text: text,
                   element: element,
                   range: read.range
               ) {
                applySelection(capture, pid: observedPID)
            } else if let known = snapshotElement, CFEqual(known, element) {
                selectedTextBeforeClick = nil
                snapshotElement = nil
                clearConsumedSelectionIfCaret(from: element)
            }
            return
        }
        guard let capture = SelectedTextService.captureSelection(from: element, application: application),
              !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            selectedTextBeforeClick = nil
            snapshotElement = nil
            clearConsumedSelectionIfCaret(from: element)
            return
        }
        applySelection(capture, pid: observedPID)
    }

    private func applySelection(
        _ capture: SelectedTextService.SelectionCapture,
        pid: pid_t
    ) {
        if let consumedSelection, !consumedSelection.matchesSelection(capture) {
            model?.invalidateCapturedSelection()
            self.consumedSelection = nil
        }
        selectedTextBeforeClick = (capture, pid)
        snapshotElement = capture.element
    }

    private func stopAXObserver() {
        if let observer = axObserver {
            if let observedElement {
                _ = AXObserverRemoveNotification(
                    observer, observedElement, kAXSelectedTextChangedNotification as CFString
                )
            }
            if let observedApplication {
                _ = AXObserverRemoveNotification(
                    observer, observedApplication, kAXFocusedUIElementChangedNotification as CFString
                )
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        observedApplication = nil
        observedElement = nil
        observedPID = nil
    }

    func cancel() {
        cancel(notice: nil)
    }

    private func cancel(notice: String?) {
        interactionID = UUID()
        timeoutTask?.cancel()
        timeoutTask = nil
        stopEscapeMonitor()
        watcher.stop()
        finishSelection(returning: false)
        interactionTask?.cancel()
        interactionTask = nil
        if let notice { model?.showNotice(notice) }
        model?.selectCancelled()
    }

    private func requestAccessibilityPermission(host: DropletHost, model: TranslateModel) {
        guard host.isGranted(.accessibility) else {
            model.showNotice(L10n.tr("permission.accessibility"))
            return
        }
        switch host.permissions.status(for: .accessibility) {
        case .notDetermined:
            guard permissionTask == nil else { return }
            permissionTask = Task { [weak self] in
                let status = await host.permissions.request(.accessibility)
                guard let self else { return }
                self.permissionTask = nil
                guard let model = self.model else { return }
                if status == .granted, host.isGranted(.accessibility), AXIsProcessTrusted() {
                    self.startSelectionObserver()
                    self.requestSelection()
                } else {
                    if status == .denied || status == .granted {
                        host.permissions.openSystemSettings(for: .accessibility)
                    }
                    model.showNotice(L10n.tr("permission.accessibility"))
                }
            }
        case .denied:
            host.permissions.openSystemSettings(for: .accessibility)
            model.showNotice(L10n.tr("permission.accessibility"))
        case .granted:
            host.permissions.openSystemSettings(for: .accessibility)
            model.showNotice(L10n.tr("permission.accessibility"))
        case .unavailable:
            model.showNotice(L10n.tr("permission.unavailable"))
        @unknown default:
            model.showNotice(L10n.tr("permission.unavailable"))
        }
    }

    private func dragReadFailed(requestID: UUID) {
        guard interactionID == requestID, let host, let model else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            selectionFailure = L10n.tr("select.readFailed")
            finishSelection(returning: false)
            return
        }
        guard hasAccessibilityPermission else {
            selectionFailure = L10n.tr("permission.accessibility")
            finishSelection(returning: false)
            return
        }
        guard host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite) else {
            selectionFailure = L10n.tr("permission.clipboard")
            finishSelection(returning: false)
            return
        }
        guard !IsSecureEventInputEnabled() else {
            selectionFailure = L10n.tr("select.readFailed")
            finishSelection(returning: false)
            return
        }
        guard selectionContinuation != nil else {
            selectionFailure = L10n.tr("select.readFailed")
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let copyPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let text = await ClipboardFallback().readSelection(host: host)
            guard self.interactionID == requestID, self.hasAccessibilityPermission,
                  host.isGranted(.clipboardRead), host.isGranted(.clipboardWrite) else {
                self.selectionFailure = L10n.tr("permission.clipboard")
                self.finishSelection(returning: false)
                return
            }
            if let text {
                self.consumeText(text, model: model, clearPID: copyPID)
                model.revealAfterShelfHidden("translate")
                self.finishSelection(returning: true)
            } else {
                self.selectionFailure = L10n.tr("select.readFailed")
                self.finishSelection(returning: false)
            }
            if let timeoutTask = self.timeoutTask {
                timeoutTask.cancel()
                self.timeoutTask = nil
            }
        }
    }

    private func finishSelection(returning result: Bool) {
        guard let continuation = selectionContinuation else { return }
        selectionContinuation = nil
        continuation.resume(returning: result)
    }

    private func ingest(_ capture: SelectedTextService.SelectionCapture, into model: TranslateModel) {
        stopEscapeMonitor()
        watcher.stop()
        model.selectCancelled()
        let collapsed = capture.collapseIfUnchanged(log: { self.host?.log.info($0) })
        consumedSelection = collapsed ? nil : capture
        if collapsed {
            selectedTextBeforeClick = nil
            snapshotElement = nil
        }
        model.ingestCaptured(capture.text, onSelectionInvalidated: { [weak self] in
            guard let self,
                  let current = self.selectedTextBeforeClick?.capture,
                  capture.matchesSelection(current) else { return }
            self.selectedTextBeforeClick = nil
            self.snapshotElement = nil
        })
    }

    private func isAlreadyConsumed(_ capture: SelectedTextService.SelectionCapture) -> Bool {
        consumedSelection?.matchesSelection(capture) == true
    }

    private func watchForEscape(requestID: UUID) {
        stopEscapeMonitor() // Clear any existing monitor first
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in
                guard let self, self.interactionID == requestID else { return }
                self.host?.log.info("Select: cancelled with Escape")
                self.stopEscapeMonitor()
                self.cancel()
            }
        }
        if escapeMonitor == nil {
            host?.log.info("Select: Escape monitor unavailable")
        }
    }

    private func stopEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func clearConsumedSelectionIfCaret(from element: AXUIElement) {
        guard let consumed = consumedSelection,
              consumed.matchesElement(element),
              SelectedTextService.selectionIsCollapsed(on: element) else { return }
        consumedSelection = nil
    }
}
