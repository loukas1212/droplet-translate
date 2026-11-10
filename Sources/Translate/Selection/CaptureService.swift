import AppKit
import DroppyKit
import Foundation
import ScreenCaptureKit
import Vision

enum CaptureError: Error, Equatable {
    case noDisplay
    case emptyCrop
    case permissionDenied
    case unavailable
}

private enum OCRLanguageSupport {
    static let languages = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []

    /// An empty hint lets Vision detect the language: about four milliseconds,
    /// and it covers scripts a fixed list would miss.
    static func hint(for languageID: String?) -> [String] {
        guard let languageID else { return [] }
        let code = Locale.Language(identifier: languageID).languageCode?.identifier ?? languageID
        let preferred = code == "th" ? "th-TH" : code == "en" ? "en-US" : nil
        if let preferred, languages.contains(preferred) { return [preferred] }
        guard code != "zh" else { return languages.filter { $0.hasPrefix("zh-") }.sorted().prefix(1).map { $0 } }
        return languages.filter {
            Locale.Language(identifier: $0).languageCode?.identifier == code
        }.sorted().prefix(1).map { $0 }
    }
}

private final class OCRCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var request: VNRequest?
    private var finished = false

    func install(_ continuation: CheckedContinuation<String?, Never>) {
        lock.lock()
        let resumeImmediately = finished
        if !finished { self.continuation = continuation }
        lock.unlock()
        if resumeImmediately { continuation.resume(returning: nil) }
    }

    func install(_ request: VNRequest) {
        lock.lock()
        let cancelImmediately = finished
        if !finished { self.request = request }
        lock.unlock()
        if cancelImmediately { request.cancel() }
    }

    func finish(_ result: String?, cancel: Bool = false) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let request = self.request
        self.request = nil
        lock.unlock()
        if cancel { request?.cancel() }
        continuation?.resume(returning: result)
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

private struct OCRLine {
    let string: String
    let box: CGRect
}

/// One visual row: a line of prose, or the cells of a list or a table that sit
/// side by side.
private struct OCRRow {
    var lines: [OCRLine]

    var box: CGRect {
        lines.dropFirst().reduce(lines[0].box) { $0.union($1.box) }
    }

    var text: String {
        lines.map(\.string).joined(separator: " ")
    }

    var startsList: Bool {
        isListMarker(lines[0].string)
    }

    /// A byline or a row of metadata: cells parted by bullets. It keeps its
    /// own line, and the prose below it starts a paragraph.
    var isMeta: Bool {
        lines.count == 1 && !startsList
            && lines[0].string.components(separatedBy: "•").count >= 3
    }

    /// One observation: a line of prose, not a row of columns.
    var isProse: Bool { lines.count == 1 && !isMeta }

    /// Two observations share a row when their boxes sit on each other; the
    /// columns of one table row do, two lines of prose do not.
    func overlaps(_ line: OCRLine) -> Bool {
        let overlap = min(box.maxY, line.box.maxY) - max(box.minY, line.box.minY)
        return overlap > min(box.height, line.box.height) * 0.5
    }
}

/// The marks that begin a list item or a menu entry. A line that starts with
/// one keeps its own line, so a list never melts into one sentence.
private func isListMarker(_ line: String) -> Bool {
    guard let first = line.first else { return false }
    if "•·‣◦▪▫●○■□–—*+>|-".contains(first) { return true }
    // "1." "2)" "(3)" "a." "b)" "iv."
    let head = line.prefix { !$0.isWhitespace }
    guard !head.isEmpty, head.count <= 5 else { return false }
    let numbered = head.drop { $0.isNumber || $0 == "(" || $0 == ")" || $0 == "." }
    if numbered.isEmpty, head.contains(where: \.isNumber) { return true }
    let letters = head.drop { $0.isLetter || $0 == "(" || $0 == ")" || $0 == "." }
    let word = head.filter(\.isLetter)
    return letters.isEmpty && head.hasSuffix(".") && (1...2).contains(word.count)
}

/// Permission gate, region pick, screenshot and OCR. Owns no UI.
@MainActor
final class CaptureService {
    private var host: DropletHost?
    private weak var model: TranslateModel?
    private var picked: (rect: CGRect, screen: NSScreen)?
    private var working = false
    private var recognitionStartedAt: Date?
    private var flowTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?

    private nonisolated static let recognitionQueue = DispatchQueue(
        label: "app.getdroppy.translate.ocr",
        qos: .userInitiated
    )

    func attach(host: DropletHost, model: TranslateModel) {
        self.host = host
        self.model = model
    }

    func detach() {
        flowTask?.cancel()
        flowTask = nil
        permissionTask?.cancel()
        permissionTask = nil
        RegionOverlayWindow.cancelActive()
        model?.ocrTask?.cancel()
        model?.ocrTask = nil
        host = nil
        model = nil
        picked = nil
        working = false
        recognitionStartedAt = nil
    }

    // MARK: Entry

    func requestRegion() {
        guard let host, let model, model.captureState == .idle, !working else { return }
        guard host.isGranted(.screenCapture), host.permissions.status(for: .screenCapture) == .granted else {
            requestCapturePermission(host: host, model: model)
            return
        }
        model.captureStarted()
        flowTask?.cancel()
        flowTask = Task { [weak self] in
            guard let self, let model = self.model, let host = self.host else { return }
            let result = await model.withShelfHidden {
                guard !Task.isCancelled, host.isGranted(.screenCapture),
                      host.permissions.status(for: .screenCapture) == .granted else {
                    model.showNotice(L10n.tr("permission.screenCapture"))
                    return false
                }
                let picked = await self.startPick()
                if picked { model.revealAfterShelfHidden("translate") }
                return picked
            }
            if !result {
                model.captureCancelled()
            }
        }
    }

    private func requestCapturePermission(host: DropletHost, model: TranslateModel) {
        guard host.isGranted(.screenCapture) else {
            model.showNotice(L10n.tr("permission.screenCapture"))
            return
        }
        switch host.permissions.status(for: .screenCapture) {
        case .notDetermined:
            guard permissionTask == nil else { return }
            permissionTask = Task { [weak self] in
                let status = await host.permissions.request(.screenCapture)
                guard let self, let model = self.model else { return }
                self.permissionTask = nil
                if status == .granted, host.isGranted(.screenCapture) {
                    self.requestRegion()
                } else {
                    if status == .denied { host.permissions.openSystemSettings(for: .screenCapture) }
                    model.showNotice(L10n.tr("permission.screenCapture"))
                }
            }
        case .denied:
            host.permissions.openSystemSettings(for: .screenCapture)
            model.showNotice(L10n.tr("permission.screenCapture"))
        case .unavailable:
            model.showNotice(L10n.tr("permission.unavailable"))
        case .granted:
            host.permissions.openSystemSettings(for: .screenCapture)
            model.showNotice(L10n.tr("permission.screenCapture"))
        @unknown default:
            model.showNotice(L10n.tr("permission.unavailable"))
        }
    }

    private func startPick() async -> Bool {
        guard let model else { return false }
        model.captureStarted()
        guard let p = await RegionOverlayWindow.pickRegion() else {
            model.captureCancelled()
            return false
        }
        guard !Task.isCancelled, let host, host.isGranted(.screenCapture),
              host.permissions.status(for: .screenCapture) == .granted else {
            model.captureCancelled()
            model.showNotice(L10n.tr("permission.screenCapture"))
            return false
        }
        picked = (p.rect, p.screen)
        working = true
        recognitionStartedAt = Date()
        model.captureRecognizing()
        model.ocrTask?.cancel()
        return await runOCR()
    }

    // MARK: Screenshot + OCR

    private func runOCR() async -> Bool {
        guard let model, let job = picked else { return false }
        let languageHint = model.sourceID == TranslateModel.auto ? nil : model.sourceID
        guard let host, host.isGranted(.screenCapture),
              host.permissions.status(for: .screenCapture) == .granted else {
            model.showNotice(L10n.tr("permission.screenCapture"))
            reset(failed: false)
            return false
        }
        let task = Task { [weak self] () throws -> String? in
            guard let self else { return nil }
            let screenshotStartedAt = Date()
            let image = try await self.screenshot(screen: job.screen, rect: job.rect)
            self.model?.note("performance screenshotMs=\(Self.elapsedMilliseconds(since: screenshotStartedAt))")
            guard self.host?.isGranted(.screenCapture) == true,
                  self.host?.permissions.status(for: .screenCapture) == .granted else {
                throw CaptureError.permissionDenied
            }
            let ocrStartedAt = Date()
            let text = await Self.recognizeWithTimeout(image: image, languageID: languageHint)
            self.model?.note("performance ocrMs=\(Self.elapsedMilliseconds(since: ocrStartedAt))")
            return text
        }
        model.ocrTask = task
        do {
            let text = try await task.value
            guard !Task.isCancelled else { reset(failed: false); return false }
            return finish(text: text)
        } catch {
            guard !Task.isCancelled else { reset(failed: false); return false }
            model.showNotice((error as? CaptureError) == .permissionDenied
                ? L10n.tr("permission.screenCapture") : L10n.tr("capture.failed"))
            reset(failed: true)
            return false
        }
    }

    private func finish(text: String?) -> Bool {
        guard let model else { return false }
        model.ocrTask = nil
        // The panel floats next to the picked region, so the eye stays put.
        if let job = picked {
            model.rememberCaptureRegion(job.rect, screen: job.screen)
        }
        if let recognitionStartedAt {
            model.note("performance captureToOCRMs=\(Self.elapsedMilliseconds(since: recognitionStartedAt))")
        }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            picked = nil
            working = false
            recognitionStartedAt = nil
        }
        guard !trimmed.isEmpty else {
            model.note(L10n.tr("ocr.failed"))
            model.showNotice(L10n.tr("ocr.failed"))
            model.captureFailed()
            return false
        }
        model.ingestCaptured(trimmed)
        model.captureFinished()
        return true
    }

    private func reset(failed: Bool) {
        model?.ocrTask = nil
        picked = nil
        working = false
        recognitionStartedAt = nil
        if failed {
            model?.captureFailed()
        } else {
            model?.captureFinished()
        }
    }

    /// Captures just the selected rectangle; if ScreenCaptureKit rejects it,
    /// captures the display and crops.
    private func screenshot(screen: NSScreen, rect: CGRect) async throws -> CGImage {
        do {
            let image = try await Self.captureDisplay(
                screen,
                sourceRect: rect,
                log: { [weak self] in self?.model?.note($0) }
            )
            return await Task.detached(priority: .userInitiated) {
                Self.downscaled(image)
            }.value
        } catch {
            // Fall through to the full-display crop.
        }

        let full = try await Self.captureDisplay(screen)
        let scale = screen.backingScaleFactor
        let selectedRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        return try await Task.detached(priority: .userInitiated) {
            let crop = selectedRect.intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
            guard !crop.isNull, !crop.isEmpty, let cropped = full.cropping(to: crop.integral) else {
                throw CaptureError.emptyCrop
            }
            return Self.downscaled(cropped)
        }.value
    }

    private static func captureDisplay(
        _ screen: NSScreen,
        sourceRect: CGRect? = nil,
        log: ((String) -> Void)? = nil
    ) async throws -> CGImage {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let contentStartedAt = Date()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        log?("performance windowListMs=\(elapsedMilliseconds(since: contentStartedAt))")
        guard let display = (id.flatMap { want in content.displays.first(where: { $0.displayID == want }) }
            ?? content.displays.first) else {
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        if let sourceRect {
            let scale = screen.backingScaleFactor
            config.width = Int(ceil(sourceRect.width * scale))
            config.height = Int(ceil(sourceRect.height * scale))
            config.sourceRect = sourceRect
        } else {
            config.width = display.width
            config.height = display.height
        }
        config.scalesToFit = false
        config.capturesAudio = false
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Full-res screenshots only slow Vision down; 2048px on the long edge is enough.
    nonisolated static func downscaled(_ image: CGImage, longEdge: Int = 2048) -> CGImage {
        let scale = min(1, Double(longEdge) / Double(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Returns after ten seconds even if Vision is still unwinding. The serial
    /// queue stops a timed-out request from overlapping the next one.
    static func recognizeWithTimeout(image: CGImage, languageID: String?) async -> String? {
        let completion = OCRCompletion()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                recognitionQueue.async {
                    guard !completion.isFinished else { return }
                    Self.recognize(image: image, languageID: languageID, completion: completion)
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10) {
                    completion.finish(nil, cancel: true)
                }
            }
        } onCancel: {
            completion.finish(nil, cancel: true)
        }
    }

    /// Accurate model, lines ordered top to bottom and grouped into paragraphs.
    private nonisolated static func recognize(
        image: CGImage,
        languageID: String?,
        completion: OCRCompletion
    ) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let languageHints = OCRLanguageSupport.hint(for: languageID)
        if languageHints.isEmpty {
            // The source is not known yet, so let Vision detect it.
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languageHints
        }
        completion.install(request)
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results, !observations.isEmpty else {
            completion.finish(nil)
            return
        }
        var lines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLine(string: candidate.string, box: observation.boundingBox)
        }
        guard !lines.isEmpty else {
            completion.finish(nil)
            return
        }
        let heights = lines.map(\.box.height).sorted()
        let medianHeight = heights[heights.count / 2]
        // A mark inside a logo or an icon reads as a lone character, smaller
        // than the text around it; it would become a line of its own.
        lines = lines.filter { !isStray($0, medianHeight: medianHeight) }
        lines.sort {
            let dy = abs($0.box.midY - $1.box.midY)
            if dy > 0.02 { return $0.box.midY > $1.box.midY }
            return $0.box.midX < $1.box.midX
        }
        guard !lines.isEmpty else {
            completion.finish(nil)
            return
        }
        // One visual row per line of the picture: observations that sit on each
        // other are the cells of that row — a menu item and its shortcut, the
        // columns of a table. A cell whose centre sits a hair lower than its
        // neighbour still belongs to the row it overlaps.
        var rows: [OCRRow] = []
        for line in lines {
            let match = rows.indices.suffix(3).last { rows[$0].overlaps(line) }
            if let match {
                rows[match].lines.append(line)
            } else {
                rows.append(OCRRow(lines: [line]))
            }
        }
        for index in rows.indices {
            rows[index].lines.sort { $0.box.minX < $1.box.minX }
        }
        let text = Self.layout(rows: rows, medianHeight: medianHeight)
        completion.finish(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text)
    }

    /// A lone character much smaller than the text is a mark in an icon, not
    /// a line the user meant to capture.
    nonisolated fileprivate static func isStray(_ line: OCRLine, medianHeight: CGFloat) -> Bool {
        line.string.count == 1 && line.box.height < medianHeight * 0.6
    }

    /// The picture's lines as text: one line per row, a blank line across a
    /// paragraph break. Rows that read as one paragraph join into one line,
    /// using the block's own width rather than the page's, so a paragraph in a
    /// narrow column still joins. A list, menu or table row keeps its line.
    nonisolated fileprivate static func layout(rows: [OCRRow], medianHeight: CGFloat) -> String {
        guard let first = rows.first else { return "" }
        let margin = medianHeight * 0.8
        // A wrapped line sits close to the line above it; a blank line is
        // roughly a line and a half.
        let gapLimit = medianHeight * 0.9

        // A block is the run of rows that could be one paragraph: a blank gap,
        // a table row or a new list item ends it. The block's own right edge
        // says whether a line was wrapped — a paragraph in a narrow column
        // still reaches its own margin, while a menu's short rows do not.
        var blockStarts = [0]
        for index in rows.indices.dropFirst() {
            let previous = rows[index - 1]
            let row = rows[index]
            let gap = previous.box.minY - row.box.maxY
            if gap > gapLimit || !previous.isProse || !row.isProse || row.startsList {
                blockStarts.append(index)
            }
        }
        blockStarts.append(rows.count)
        var paragraphEdges = [CGFloat?](repeating: nil, count: rows.count)
        for (start, end) in zip(blockStarts, blockStarts.dropFirst()) {
            let block = rows[start..<end]
            guard let first = block.first, let last = block.last else { continue }
            let edge = block.map(\.box.maxX).max() ?? 0
            let width = edge - (block.map(\.box.minX).min() ?? first.box.minX)
            let average = block.map(\.box.width).reduce(0, +) / CGFloat(block.count)
            let lastShort = last.box.maxX < edge - margin
            // A paragraph's lines are mostly long and stop short on the last
            // line; a menu's short rows average much narrower than its widest
            // one. A list item is a paragraph of its own, so its wrapped lines
            // join but the next item starts a new block.
            let twoLineParagraph = block.count == 2
                && first.box.width >= width * 0.7
                && lastShort
            let isParagraph = first.startsList
                || twoLineParagraph
                || (block.count >= 3 && width > 0 && average >= width * 0.7 && lastShort)
            if isParagraph {
                for index in start..<end { paragraphEdges[index] = edge }
            }
        }

        var text = first.text
        for (previousIndex, rowIndex) in zip(rows.indices, rows.indices.dropFirst()) {
            let previous = rows[previousIndex]
            let row = rows[rowIndex]
            let gap = previous.box.minY - row.box.maxY
            let inParagraph = paragraphEdges[previousIndex] != nil
            let wrapped = inParagraph && previous.isProse && row.isProse && !row.startsList
            if gap > gapLimit || previous.isMeta {
                text += "\n\n" + row.text
            } else if wrapped {
                text += " " + row.text
            } else {
                text += "\n" + row.text
            }
        }
        return text
    }

    /// Synthetic rows in Vision's own coordinates: origin bottom left, y up.
    static func checkOCRLayoutRules() {
        func line(_ string: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 0.04) -> OCRLine {
            OCRLine(string: string, box: CGRect(x: x, y: y, width: width, height: height))
        }
        func rows(_ lines: [OCRLine]) -> [OCRRow] {
            lines.map { OCRRow(lines: [$0]) }
        }

        // A mark in an icon is smaller than the text and never a line.
        assert(isStray(line("e", x: 0.06, y: 0.94, width: 0.04, height: 0.012), medianHeight: 0.024))
        assert(!isStray(line("I", x: 0.15, y: 0.94, width: 0.02), medianHeight: 0.024))

        // A byline of bulleted cells keeps its line and parts the paragraph
        // below it, even when the gap is only a line's.
        let byline = layout(
            rows: rows([
                line("Eric S. Raymond • @esrtweet • 18h", x: 0.15, y: 0.90, width: 0.60),
                line("I have deliberately chosen the way", x: 0.15, y: 0.85, width: 0.70),
                line("the paragraph goes on.", x: 0.15, y: 0.80, width: 0.30),
            ]),
            medianHeight: 0.04
        )
        assert(byline == "Eric S. Raymond • @esrtweet • 18h\n\nI have deliberately chosen the way the paragraph goes on.", byline)

        // A wrapped paragraph joins; a list keeps one item per line.
        let prose = layout(
            rows: rows([
                line("The quick brown fox", x: 0.10, y: 0.80, width: 0.70),
                line("jumps over the dog.", x: 0.10, y: 0.74, width: 0.30),
            ]),
            medianHeight: 0.04
        )
        assert(prose == "The quick brown fox jumps over the dog.", prose)

        // Ragged lines: none of them reach one common margin, but they fill
        // the paragraph's own column and the last one stops short.
        func wrapped(_ string: String, y: CGFloat, width: CGFloat) -> OCRLine {
            line(string, x: 0.18, y: y, width: width)
        }
        let ragged = layout(
            rows: rows([
                wrapped("I have deliberately chosen", y: 0.80, width: 0.45),
                wrapped("to keep the way I work", y: 0.75, width: 0.34),
                wrapped("with large language models", y: 0.70, width: 0.50),
                wrapped("extremely simple and even", y: 0.65, width: 0.32),
                wrapped("a little primitive in how", y: 0.60, width: 0.43),
                wrapped("it asks for code and then", y: 0.55, width: 0.47),
                wrapped("keeps the conversation going", y: 0.50, width: 0.44),
                wrapped("without any extra tools at all.", y: 0.45, width: 0.44),
                wrapped("That is it.", y: 0.40, width: 0.13),
            ]),
            medianHeight: 0.04
        )
        assert(!ragged.contains("\n"), ragged)

        // A paragraph of two lines is too short to judge by its average, and
        // the last line still stops short.
        let twoLines = layout(
            rows: rows([
                line("I have yet to see convincing evidence", x: 0.18, y: 0.80, width: 0.44),
                line("that this is losing me productivity.", x: 0.18, y: 0.75, width: 0.30),
            ]),
            medianHeight: 0.04
        )
        assert(twoLines == "I have yet to see convincing evidence that this is losing me productivity.", twoLines)

        let list = layout(
            rows: rows([
                line("• First item", x: 0.10, y: 0.80, width: 0.30),
                line("• Second item", x: 0.10, y: 0.74, width: 0.32),
            ]),
            medianHeight: 0.04
        )
        assert(list == "• First item\n• Second item", list)

        // A paragraph in a narrow column uses its own right edge; a wider
        // heading above it does not make its lines look short.
        let narrow = layout(
            rows: rows([
                line("A wide heading over the column", x: 0.10, y: 0.90, width: 0.80),
                line("One paragraph in a narrow", x: 0.10, y: 0.80, width: 0.34),
                line("column still reads as one line", x: 0.10, y: 0.74, width: 0.32),
                line("when it ends.", x: 0.10, y: 0.70, width: 0.14),
            ]),
            medianHeight: 0.04
        )
        assert(narrow == "A wide heading over the column\n\nOne paragraph in a narrow column still reads as one line when it ends.", narrow)

        // A dropdown keeps one entry per line even when one entry is the
        // widest row of its block.
        let dropdown = layout(
            rows: rows([
                line("Open", x: 0.10, y: 0.80, width: 0.10),
                line("Save As…", x: 0.10, y: 0.76, width: 0.20),
                line("Export as PDF", x: 0.10, y: 0.72, width: 0.26),
                line("Quit", x: 0.10, y: 0.68, width: 0.08),
            ]),
            medianHeight: 0.04
        )
        assert(dropdown == "Open\nSave As…\nExport as PDF\nQuit", dropdown)

        // A changelog: short section headings, then hyphen bullets longer than
        // the heading. Each item keeps its line and a blank line parts sections.
        let changelog = layout(
            rows: rows([
                line("New Features", x: 0.06, y: 0.90, width: 0.12, height: 0.047),
                line("- Added an offer when opening from disk.", x: 0.03, y: 0.82, width: 0.87, height: 0.061),
                line("Bug Fixes", x: 0.06, y: 0.66, width: 0.08, height: 0.055),
                line("- Fixed the crash on eject.", x: 0.03, y: 0.58, width: 0.83, height: 0.054),
                line("- Fixed Cursor staying on Signing in.", x: 0.03, y: 0.50, width: 0.65, height: 0.082),
                line("- Fixed the notch right-click setting.", x: 0.03, y: 0.42, width: 0.76, height: 0.074),
                line("- Fixed the Settings window name.", x: 0.03, y: 0.35, width: 0.77, height: 0.054),
                line("- Fixed Clipboard content.", x: 0.03, y: 0.28, width: 0.47, height: 0.061),
                line("Refinements", x: 0.06, y: 0.14, width: 0.10, height: 0.047),
                line("- Improved the export logs.", x: 0.03, y: 0.05, width: 0.94, height: 0.075),
            ]),
            medianHeight: 0.061
        )
        let changelogExpected = """
        New Features
        - Added an offer when opening from disk.

        Bug Fixes
        - Fixed the crash on eject.
        - Fixed Cursor staying on Signing in.
        - Fixed the notch right-click setting.
        - Fixed the Settings window name.
        - Fixed Clipboard content.

        Refinements
        - Improved the export logs.
        """
        assert(changelog == changelogExpected, changelog)

        // A first-line indent is part of the paragraph, not a new one.
        let indented = layout(
            rows: rows([
                line("An indented first line opens", x: 0.18, y: 0.80, width: 0.30),
                line("the paragraph and its body", x: 0.10, y: 0.74, width: 0.36),
                line("runs to the end.", x: 0.10, y: 0.70, width: 0.16),
            ]),
            medianHeight: 0.04
        )
        assert(indented == "An indented first line opens the paragraph and its body runs to the end.", indented)

        // A menu entry and its shortcut are one row, not two lines.
        let menu = OCRRow(lines: [
            line("Open…", x: 0.10, y: 0.80, width: 0.20),
            line("⌘O", x: 0.70, y: 0.80, width: 0.10),
        ])
        assert(menu.text == "Open… ⌘O", menu.text)
        assert(menu.isProse == false)

        // A gap of a line height parts paragraphs.
        let parted = layout(
            rows: rows([
                line("One paragraph.", x: 0.10, y: 0.80, width: 0.30),
                line("Another one.", x: 0.10, y: 0.66, width: 0.28),
            ]),
            medianHeight: 0.04
        )
        assert(parted == "One paragraph.\n\nAnother one.", parted)
    }

    private nonisolated static func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
