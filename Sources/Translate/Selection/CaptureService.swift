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
        let lines = observations
            .compactMap { observation -> OCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRLine(string: candidate.string, box: observation.boundingBox)
            }
            .sorted {
                let dy = abs($0.box.midY - $1.box.midY)
                if dy > 0.02 { return $0.box.midY > $1.box.midY }
                return $0.box.midX < $1.box.midX
            }
        guard !lines.isEmpty else {
            completion.finish(nil)
            return
        }
        // A paragraph break is a gap of roughly one line height; wrapped lines
        // inside a paragraph sit much tighter.
        let medianHeight = lines.map(\.box.height).sorted()[lines.count / 2]
        var paragraphs: [[String]] = []
        var current: [String] = [lines[0].string]
        for (previous, line) in zip(lines, lines.dropFirst()) {
            if previous.box.minY - line.box.maxY > medianHeight * 0.6 {
                paragraphs.append(current)
                current = [line.string]
            } else {
                current.append(line.string)
            }
        }
        paragraphs.append(current)
        // The reference app collapses wrapped lines inside a paragraph.
        let text = paragraphs.map { $0.joined(separator: " ") }.joined(separator: "\n\n")
        completion.finish(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text)
    }

    private nonisolated static func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }
}
