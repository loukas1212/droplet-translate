import AppKit
import ApplicationServices
import Foundation

/// Reads selected text from an app's focused accessibility element.
@MainActor
enum SelectedTextService {
    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString

    /// AX calls cross IPC and can stall for the whole messaging timeout, while
    /// the droplet shares the host's process. Every walk therefore runs on a
    /// wall-clock budget; a hung app is abandoned instead of freezing Droppy.
    private static let walkBudget: TimeInterval = 1.0
    private static let searchBudget: TimeInterval = 1.5

    struct SelectionCapture {
        let text: String
        private let pid: pid_t
        /// The focused element, or an ancestor when the app only exposes the
        /// selection there.
        let element: AXUIElement
        fileprivate let range: SelectionRange?

        fileprivate init(text: String, element: AXUIElement, range: SelectionRange?) {
            self.text = text
            self.element = element
            self.range = range
            var pid: pid_t = 0
            _ = AXUIElementGetPid(element, &pid)
            self.pid = pid
        }

        func matchesSelection(_ other: SelectionCapture) -> Bool {
            guard pid == other.pid, text == other.text, matchesElement(other.element) else { return false }
            switch (range, other.range) {
            case (nil, nil): return true
            case let (left?, right?): return left.matches(right)
            default: return false
            }
        }

        func matchesElement(_ other: AXUIElement) -> Bool { CFEqual(element, other) }

        @discardableResult
        @MainActor
        func collapseIfUnchanged(log: ((String) -> Void)? = nil) -> Bool {
            guard let range else {
                log?("Select: cannot clear highlight; source app exposes no writable selection range")
                return false
            }
            AXUIElementSetMessagingTimeout(element, 0.25)
            let current = SelectedTextService.selectedTextRead(from: element, includeTextMarkerRange: true)
            guard current.text == text, let currentRange = current.range,
                  range.matches(currentRange) else {
                log?("Select: kept highlight; source selection changed before translation completed")
                return false
            }

            let status: AXError
            switch (range, currentRange) {
            case let (.characters(original), .characters):
                guard original.location >= 0, original.length > 0 else { return false }
                let (caretLocation, overflow) = original.location.addingReportingOverflow(original.length)
                guard !overflow else { return false }
                var caret = CFRange(location: caretLocation, length: 0)
                guard let value = AXValueCreate(.cfRange, &caret) else { return false }
                guard SelectedTextService.attributeIsSettable(kAXSelectedTextRangeAttribute as CFString, of: element) else {
                    log?("Select: source app does not allow clearing this selection")
                    return false
                }
                status = AXUIElementSetAttributeValue(
                    element, kAXSelectedTextRangeAttribute as CFString, value
                )
            case let (.marker, .marker(live)):
                guard SelectedTextService.attributeIsSettable("AXSelectedTextMarkerRange" as CFString, of: element) else {
                    log?("Select: source app does not allow clearing this text marker selection")
                    return false
                }
                let markerRange = live as! AXTextMarkerRange
                let endMarker = AXTextMarkerRangeCopyEndMarker(markerRange)
                let collapsed = AXTextMarkerRangeCreate(kCFAllocatorDefault, endMarker, endMarker)
                status = AXUIElementSetAttributeValue(
                    element, "AXSelectedTextMarkerRange" as CFString, collapsed
                )
            default:
                log?("Select: kept highlight; source selection range type changed")
                return false
            }

            if status == .success {
                log?("Select: cleared source highlight after translation")
                return true
            }
            log?("Select: could not clear source highlight (AX \(status.rawValue))")
            return false
        }
    }

    enum SelectionRange {
        case characters(CFRange)
        case marker(CFTypeRef)

        func matches(_ other: SelectionRange) -> Bool {
            switch (self, other) {
            case let (.characters(lhs), .characters(rhs)):
                return lhs.location == rhs.location && lhs.length == rhs.length
            case let (.marker(lhs), .marker(rhs)):
                guard CFGetTypeID(lhs) == AXTextMarkerRangeGetTypeID(),
                      CFGetTypeID(rhs) == AXTextMarkerRangeGetTypeID() else { return false }
                let left = lhs as! AXTextMarkerRange
                let right = rhs as! AXTextMarkerRange
                let leftStart = AXTextMarkerRangeCopyStartMarker(left)
                let rightStart = AXTextMarkerRangeCopyStartMarker(right)
                let leftEnd = AXTextMarkerRangeCopyEndMarker(left)
                let rightEnd = AXTextMarkerRangeCopyEndMarker(right)
                return SelectedTextService.textMarkersEqual(leftStart, rightStart)
                    && SelectedTextService.textMarkersEqual(leftEnd, rightEnd)
            default:
                return false
            }
        }
    }

    struct SelectedTextRead {
        let text: String?
        let range: SelectionRange?
        let diagnostics: String
    }

    /// For the cheap refresh, where the element is already known.
    static func capture(
        text: String,
        element: AXUIElement,
        range: SelectionRange?
    ) -> SelectionCapture? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return SelectionCapture(text: text, element: element, range: range)
    }

    static func readSelectedText(log: ((String) -> Void)? = nil) -> String? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return readSelectedText(inApplicationPID: pid, log: log)
    }

    /// Chromium keeps its web accessibility tree dormant until a client asks
    /// for it. Prefer AXManualAccessibility; AXEnhancedUserInterface can affect
    /// window-move animation in the target app.
    static func enableWebContentAccessibility(
        inApplicationPID pid: pid_t,
        bundleIdentifier: String?,
        log: ((String) -> Void)? = nil
    ) -> Bool {
        guard pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier,
              isChromiumBrowser(bundleIdentifier) else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)

        var namesValue: CFArray?
        guard AXUIElementCopyAttributeNames(app, &namesValue) == .success,
              let names = namesValue as? [String] else {
            log?("Select: cannot inspect web accessibility controls for pid=\(pid)")
            return false
        }

        var attributes: [CFString] = []
        if names.contains(manualAccessibilityAttribute as String) {
            attributes.append(manualAccessibilityAttribute)
        }
        if names.contains(enhancedUserInterfaceAttribute as String) {
            attributes.append(enhancedUserInterfaceAttribute)
        }
        for attribute in attributes {
            var current: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attribute, &current) == .success,
               (current as? NSNumber)?.boolValue == true { return false }

            let status = AXUIElementSetAttributeValue(app, attribute, kCFBooleanTrue)
            guard status == .success else {
                log?("Select: web accessibility refused via \(attribute as String) for pid=\(pid) (AX \(status.rawValue))")
                continue
            }
            log?("Select: web accessibility enabled via \(attribute as String) for pid=\(pid)")
            return true
        }
        return false
    }

    private static func isChromiumBrowser(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return [
            "com.google.Chrome", "org.chromium.", "com.brave.Browser",
            "com.microsoft.edgemac", "com.pushplaylabs.sidekick", "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera", "com.sigmaos.sigmaos.macos", "com.quark.desktop",
            "net.imput.helium", "ai.perplexity.comet", "com.openai.atlas",
            "org.ecosia.browser", "company.thebrowser."
        ].contains { prefix in
            bundleIdentifier == prefix || bundleIdentifier.hasPrefix(prefix + ".") || prefix.hasSuffix(".") && bundleIdentifier.hasPrefix(prefix)
        }
    }

    static func readSelectedText(inApplicationPID pid: pid_t, log: ((String) -> Void)? = nil) -> String? {
        captureSelection(inApplicationPID: pid, log: log)?.text
    }

    static func captureSelection(inApplicationPID pid: pid_t, log: ((String) -> Void)? = nil) -> SelectionCapture? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var focusedUI: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedUI
        )
        var focusedElement: AXUIElement?
        if focusError == .success, let focusedUI,
           CFGetTypeID(focusedUI) == AXUIElementGetTypeID() {
            let element = focusedUI as! AXUIElement
            focusedElement = element
            logElementMetadata(element, pid: pid, log: log)
            if let capture = captureSelection(from: element, application: app, log: log) {
                log?("Select: app pid=\(pid), selected-text=chars=\(capture.text.count)")
                return capture
            }
        }
        log?("Select: app pid=\(pid), focused selection unavailable (AX \(focusError.rawValue)); checking window")
        let capture = captureSelection(inWindowOf: app, excluding: focusedElement, log: log)
        log?("Select: app pid=\(pid), window selection=\(capture.map { "chars=\($0.text.count)" } ?? "unavailable")")
        return capture
    }

    static func readSelectedText(
        in systemWide: AXUIElement,
        preferredPID: pid_t?,
        log: ((String) -> Void)? = nil
    ) -> String? {
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        ) == .success, let focusedApp,
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else {
            log?("Select: focused app unavailable; frontmost pid=\(preferredPID.map(String.init) ?? "none")")
            return nil
        }

        let appElement = focusedApp as! AXUIElement
        var pid: pid_t = 0
        _ = AXUIElementGetPid(appElement, &pid)
        guard preferredPID == nil || preferredPID == pid else {
            log?("Select: ignored stale AX focus pid=\(pid); frontmost pid=\(preferredPID ?? 0)")
            return nil
        }
        var focusedUI: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &focusedUI
        )
        guard focusError == .success, let focusedUI,
              CFGetTypeID(focusedUI) == AXUIElementGetTypeID() else {
            log?("Select: focused pid=\(pid), element unavailable (AX \(focusError.rawValue))")
            return nil
        }

        let focusedElement = focusedUI as! AXUIElement
        logElementMetadata(focusedElement, pid: pid, log: log)
        if let capture = captureSelection(from: focusedElement, application: appElement, log: log) {
            log?("Select: focused pid=\(pid), selected-text=chars=\(capture.text.count)")
            return capture.text
        }
        let text = readSelectedText(inWindowOf: appElement, log: log)
        let result = text.map { "chars=\($0.count)" } ?? "unavailable"
        log?("Select: focused pid=\(pid), window selection=\(result)")
        return text
    }

    static func readSelectedText(
        from element: AXUIElement,
        application: AXUIElement? = nil,
        log: ((String) -> Void)? = nil
    ) -> String? {
        captureSelection(from: element, application: application, log: log)?.text
    }

    static func captureSelection(
        from element: AXUIElement,
        application: AXUIElement? = nil,
        log: ((String) -> Void)? = nil
    ) -> SelectionCapture? {
        var current: AXUIElement? = element
        let deadline = Date().addingTimeInterval(Self.walkBudget)
        for depth in 0..<25 {
            guard let candidate = current else { break }
            guard Date() < deadline else {
                log?("Select: selection walk ran out of time at depth=\(depth)")
                break
            }
            AXUIElementSetMessagingTimeout(candidate, 0.25)
            let role = stringAttribute(kAXRoleAttribute, of: candidate)
            let read = selectedTextRead(from: candidate, includeTextMarkerRange: depth == 0 || role.value == "AXWebArea")
            if depth == 0, let log {
                let subrole = stringAttribute(kAXSubroleAttribute, of: candidate)
                log("Select: AX focused role=\(role.value) (\(role.status)) subrole=\(subrole.value) (\(subrole.status)); \(read.diagnostics)")
            }
            if let text = read.text {
                return SelectionCapture(text: text, element: candidate, range: read.range)
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate, kAXParentAttribute as CFString, &parent
            ) == .success, let parent,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = (parent as! AXUIElement)
        }
        return application.flatMap { captureSelection(inWindowOf: $0, log: log) }
    }

    private static func readSelectedText(inWindowOf app: AXUIElement, log: ((String) -> Void)? = nil) -> String? {
        captureSelection(inWindowOf: app, log: log)?.text
    }

    private static func captureSelection(
        inWindowOf app: AXUIElement,
        excluding excludedElement: AXUIElement? = nil,
        log: ((String) -> Void)? = nil
    ) -> SelectionCapture? {
        AXUIElementSetMessagingTimeout(app, 0.25)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &windowValue
        ) == .success, let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }

        var pending: [(element: AXUIElement, depth: Int)] = [(windowValue as! AXUIElement, 0)]
        var excludedElements: [AXUIElement] = []
        if let excludedElement {
            var current: AXUIElement? = excludedElement
            for _ in 0..<25 {
                guard let candidate = current else { break }
                excludedElements.append(candidate)
                var parent: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    candidate, kAXParentAttribute as CFString, &parent
                ) == .success, let parent,
                      CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
                current = (parent as! AXUIElement)
            }
        }
        var visited = 0
        let deadline = Date().addingTimeInterval(Self.searchBudget)
        while !pending.isEmpty && visited < 128 {
            guard Date() < deadline else {
                log?("Select: window search ran out of time, visited=\(visited)")
                break
            }
            let (element, depth) = pending.removeLast()
            visited += 1
            AXUIElementSetMessagingTimeout(element, 0.25)
            if excludedElements.contains(where: { CFEqual($0, element) }) { continue }
            let role = stringAttribute(kAXRoleAttribute, of: element)
            let read = selectedTextRead(from: element, includeTextMarkerRange: role.value == "AXWebArea")
            if let text = read.text {
                log?("Select: window AX found selected text at depth=\(depth), visited=\(visited), chars=\(text.count)")
                return SelectionCapture(text: text, element: element, range: read.range)
            }
            guard depth < 6 else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &childrenValue
            ) == .success,
               let children = childrenValue as? [AXUIElement] else { continue }
            pending.append(contentsOf: children.enumerated().reversed().compactMap { index, child in
                index < 32 ? (child, depth + 1) : nil
            })
        }
        log?("Select: window AX search empty, visited=\(visited), pending=\(pending.count)")
        return nil
    }

    static func selectedTextRead(
        from element: AXUIElement,
        includeTextMarkerRange: Bool = false
    ) -> SelectedTextRead {
        var selected: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selected
        )
        if selectedStatus == .success,
           let text = selected as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let range = selectionRange(from: element, includeTextMarkerRange: includeTextMarkerRange)
            return SelectedTextRead(
                text: text,
                range: range,
                diagnostics: "selectedText=ok chars=\(text.count)"
            )
        }

        if includeTextMarkerRange,
           let marker = textMarkerRange(of: element),
           let text = string(forTextMarkerRange: marker, of: element),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return SelectedTextRead(
                text: text,
                range: .marker(marker),
                diagnostics: "textMarkerRange=ok chars=\(text.count)"
            )
        }

        var rangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        )
        guard rangeStatus == .success, let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return SelectedTextRead(
                text: nil,
                range: nil,
                diagnostics: "selectedText=AX \(selectedStatus.rawValue); selectedRange=AX \(rangeStatus.rawValue)"
            )
        }
        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 else {
            return SelectedTextRead(text: nil, range: nil, diagnostics: "selectedRange=ok length=0-or-invalid")
        }
        var value: CFTypeRef?
        let stringStatus = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard stringStatus == .success,
              let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SelectedTextRead(
                text: nil,
                range: nil,
                diagnostics: "selectedText=AX \(selectedStatus.rawValue); selectedRange=ok length=\(range.length); rangeString=AX \(stringStatus.rawValue)"
            )
        }
        return SelectedTextRead(
            text: text,
            range: .characters(range),
            diagnostics: "selectedText=AX \(selectedStatus.rawValue); selectedRange=ok length=\(range.length); rangeString=ok chars=\(text.count)"
        )
    }

    static func selectionIsCollapsed(on element: AXUIElement) -> Bool {
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) { return range.length == 0 }
        }
        if let markerRange = textMarkerRange(of: element) {
            let range = markerRange as! AXTextMarkerRange
            return textMarkersEqual(
                AXTextMarkerRangeCopyStartMarker(range),
                AXTextMarkerRangeCopyEndMarker(range)
            )
        }
        return false
    }

    nonisolated fileprivate static func textMarkersEqual(_ lhs: AXTextMarker, _ rhs: AXTextMarker) -> Bool {
        let lhsLength = AXTextMarkerGetLength(lhs)
        guard lhsLength >= 0, lhsLength == AXTextMarkerGetLength(rhs) else { return false }
        return Data(
            bytes: AXTextMarkerGetBytePtr(lhs), count: Int(lhsLength)
        ) == Data(bytes: AXTextMarkerGetBytePtr(rhs), count: Int(lhsLength))
    }

    private static func selectionRange(from element: AXUIElement, includeTextMarkerRange: Bool) -> SelectionRange? {
        var rangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
        ) == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 {
                return .characters(range)
            }
        }
        return includeTextMarkerRange ? textMarkerRange(of: element).map(SelectionRange.marker) : nil
    }

    /// Web content often exposes its selection only through the opaque text-marker API.
    private static func textMarkerRange(of element: AXUIElement) -> CFTypeRef? {
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, "AXSelectedTextMarkerRange" as CFString, &markerRange
        ) == .success, let markerRange,
           CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID() else { return nil }
        return markerRange
    }

    private static func string(forTextMarkerRange markerRange: CFTypeRef, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXStringForTextMarkerRange" as CFString,
            markerRange,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    /// Best-effort clear after the Cmd+C fallback, which leaves no
    /// `SelectionCapture` to track.
    @discardableResult
    static func clearSelection(inApplicationPID pid: pid_t, log: ((String) -> Void)? = nil) -> Bool {
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var focusedUI: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &focusedUI
        ) == .success, let focusedUI,
              CFGetTypeID(focusedUI) == AXUIElementGetTypeID() else {
            log?("Select: fallback highlight clear skipped; focused element unavailable")
            return false
        }

        let focusedElement = focusedUI as! AXUIElement
        var current: AXUIElement? = focusedElement
        let deadline = Date().addingTimeInterval(Self.walkBudget)
        for _ in 0..<25 {
            guard let element = current else { break }
            guard Date() < deadline else {
                log?("Select: highlight clear ran out of time")
                return false
            }
            AXUIElementSetMessagingTimeout(element, 0.25)

            var rangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &rangeValue
            ) == .success, let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                var range = CFRange()
                if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0,
                   attributeIsSettable(kAXSelectedTextRangeAttribute as CFString, of: element) {
                    let (location, overflow) = range.location.addingReportingOverflow(range.length)
                    if !overflow {
                        var caret = CFRange(location: location, length: 0)
                        if let value = AXValueCreate(.cfRange, &caret),
                           AXUIElementSetAttributeValue(
                               element, kAXSelectedTextRangeAttribute as CFString, value
                           ) == .success {
                            log?("Select: cleared fallback highlight")
                            return true
                        }
                    }
                }
            }

            if let marker = textMarkerRange(of: element),
               attributeIsSettable("AXSelectedTextMarkerRange" as CFString, of: element) {
                let markerRange = marker as! AXTextMarkerRange
                let endMarker = AXTextMarkerRangeCopyEndMarker(markerRange)
                let collapsed = AXTextMarkerRangeCreate(kCFAllocatorDefault, endMarker, endMarker)
                if AXUIElementSetAttributeValue(
                    element, "AXSelectedTextMarkerRange" as CFString, collapsed
                ) == .success {
                    log?("Select: cleared fallback highlight (text marker)")
                    return true
                }
            }

            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element, kAXParentAttribute as CFString, &parent
            ) == .success, let parent,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            let parentElement = parent as! AXUIElement
            current = parentElement
        }

        log?("Select: could not clear fallback highlight")
        return false
    }

    private static func attributeIsSettable(_ name: CFString, of element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name, &settable) == .success && settable.boolValue
    }

    private static func logElementMetadata(
        _ element: AXUIElement,
        pid: pid_t,
        log: ((String) -> Void)?
    ) {
        guard let log else { return }
        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)
        let selectedStatus = attributeStatus(kAXSelectedTextAttribute, of: element)
        let rangeStatus = attributeStatus(kAXSelectedTextRangeAttribute, of: element)
        var parameterized: CFArray?
        let parameterizedStatus = AXUIElementCopyParameterizedAttributeNames(element, &parameterized)
        let supportsRangeString = (parameterized as? [String])?.contains(
            kAXStringForRangeParameterizedAttribute as String
        ) ?? false
        log("Select: AX pid=\(pid) role=\(role.value) (\(role.status)) subrole=\(subrole.value) (\(subrole.status)); selectedText=\(selectedStatus); selectedRange=\(rangeStatus); rangeString=\(supportsRangeString) (AX \(parameterizedStatus.rawValue))")
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> (value: String, status: AXError) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return (status == .success ? (value as? String ?? "non-string") : "unavailable", status)
    }

    private static func attributeStatus(_ name: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return status == .success ? "ok" : "AX \(status.rawValue)"
    }
}
