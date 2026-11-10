import Foundation
import NaturalLanguage
import SwiftUI
import Translation

// Apple's Translation framework needs macOS 15, the package targets macOS 14.
// Keep every use gated here so no other file imports it.

enum PairStatus: Equatable, Sendable {
    case installed
    case needsDownload
    case unsupported

    var pairInfo: PairInfo {
        switch self {
        case .installed: .ready
        case .needsDownload: .needsDownload
        case .unsupported: .unsupported
        }
    }
}

/// Language helpers that work on every supported macOS.
enum LanguageTools {
    private static let namingLocale = Locale(identifier: "en")

    /// The dominant language as a minimal identifier, or nil when the
    /// recognizer is not confident.
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(1000)))
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return canonicalID(language.rawValue)
    }

    static func canonicalID(_ id: String) -> String {
        Locale.Language(identifier: id).languageCode?.identifier ?? id
    }

    static func name(for id: String) -> String {
        let language = Locale.Language(identifier: id)
        let code = language.languageCode?.identifier ?? id
        return namingLocale.localizedString(forIdentifier: code) ?? code
    }

    private static func groupingKey(for language: Locale.Language) -> String {
        language.languageCode?.identifier ?? language.minimalIdentifier
    }

    private static func selectionID(for language: Locale.Language) -> String {
        groupingKey(for: language)
    }

    private static func option(for language: Locale.Language) -> LanguageOption {
        let id = selectionID(for: language)
        let code = language.languageCode?.identifier ?? id
        let displayName = name(for: id)
        let menuName = "\(displayName) (\(code))"
        return LanguageOption(id: id, name: displayName, menuName: menuName)
    }

    static func systemLanguageID() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        return canonicalID(preferred)
    }

    /// True when translating between the two would be a no-op. Chinese scripts
    /// are different writing systems and stay distinct.
    static func isSameLanguage(_ a: String, _ b: String) -> Bool {
        let first = Locale.Language(identifier: a)
        let second = Locale.Language(identifier: b)
        guard let codeA = first.languageCode, let codeB = second.languageCode, codeA == codeB else {
            return false
        }
        if codeA.identifier == "zh" { return first.minimalIdentifier == second.minimalIdentifier }
        return true
    }

    static func options(for ids: [String]) -> [LanguageOption] {
        options(for: ids.map(Locale.Language.init(identifier:)))
    }

    static func options(for languages: [Locale.Language]) -> [LanguageOption] {
        var seen = Set<String>()
        let options = languages.sorted { $0.minimalIdentifier < $1.minimalIdentifier }
            .compactMap { language -> LanguageOption? in
            let key = groupingKey(for: language)
            guard seen.insert(key).inserted else { return nil }
            return option(for: language)
        }
        assert(Set(options.map(\.id)).count == options.count, "Language menu identifiers must be unique")
        return options.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame
                ? $0.menuName.localizedStandardCompare($1.menuName) == .orderedAscending
                : order == .orderedAscending
        }
    }

    static func checkLanguageIDRules() {
        let spanish = options(for: ["es-ES", "es-us", "ES-us", "es"])
        let spanishOptions = spanish.filter { $0.id == "es" }
        assert(spanishOptions.count == 1)
        assert(spanishOptions.first?.name == "Spanish")
        assert(spanishOptions.first?.menuName == "Spanish (es)")
        let chinese = options(for: ["zh-Hans", "zh-Hant"])
        let chineseOptions = chinese.filter { $0.id == "zh" }
        assert(chineseOptions.count == 1)
        assert(chineseOptions.first?.menuName == "Chinese (zh)")
        let english = options(for: ["en", "en-GB", "en-US"])
        assert(english.contains(where: { $0.id == "en" && $0.menuName == "English (en)" }))
        assert(english.filter { $0.id.hasPrefix("en") }.count == 1)
        assert(options(for: ["es-US", "es-419", "es"]).contains(where: { $0.id == "es" && $0.menuName == "Spanish (es)" }))
        assert(options(for: ["th-Thai", "th"]).filter { $0.id == "th" }.map(\.menuName) == ["Thai (th)"])
        assert(options(for: ["ru-Cyrl", "ru"]).filter { $0.id == "ru" }.map(\.menuName) == ["Russian (ru)"])
        assert(options(for: ["uk-UA", "uk"]).filter { $0.id == "uk" }.map(\.menuName) == ["Ukrainian (uk)"])
    }

    /// Shown until the system answers, and when it cannot.
    static let fallback: [LanguageOption] = options(for: [
        "ar", "zh", "nl", "en", "fr", "de", "hi", "id", "it",
        "ja", "ko", "pl", "pt-BR", "ru", "es", "th", "tr", "uk", "vi",
    ])
}

@available(macOS 15.0, *)
enum TranslationBridge {
    static func supportedLanguages() async -> [LanguageOption] {
        let languages = await LanguageAvailability().supportedLanguages
        return LanguageTools.options(for: languages)
    }

    static func pairStatus(
        source: String,
        target: String,
        approach: TranslationApproach
    ) async -> PairStatus {
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        let status: LanguageAvailability.Status
        if #available(macOS 26.4, *) {
            // Models are per strategy: a language can have the Apple
            // Intelligence models and still miss the classic ones.
            let strategy: TranslationSession.Strategy = approach == .fast ? .lowLatency : .highFidelity
            status = await LanguageAvailability(preferredStrategy: strategy)
                .status(from: sourceLanguage, to: targetLanguage)
        } else {
            status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
        }
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        default: return .unsupported
        }
    }

    /// Setting a configuration starts a `translationTask`; an equal one does
    /// nothing until invalidated. The approach is part of the identity but the
    /// framework does not expose it, so the caller passes it in.
    static func configuration(
        replacing current: TranslationSession.Configuration?,
        builtWith currentApproach: TranslationApproach?,
        source: String,
        target: String,
        approach: TranslationApproach
    ) -> TranslationSession.Configuration {
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        if var current, currentApproach == approach,
           current.source == sourceLanguage, current.target == targetLanguage {
            current.invalidate()
            return current
        }
        if #available(macOS 26.4, *) {
            // The low latency strategy answers a long text in a fraction of
            // the time, which is what makes a capture feel instant.
            let strategy: TranslationSession.Strategy = approach == .fast ? .lowLatency : .highFidelity
            return TranslationSession.Configuration(
                source: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: strategy
            )
        }
        return TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
    }
}

// MARK: - Runners

// `TranslationSession` only exists inside a SwiftUI `translationTask`, so the
// model publishes a job and these invisible modifiers carry it out.

@available(macOS 15.0, *)
private func nextConfig(
    _ current: TranslationSession.Configuration?,
    currentApproach: TranslationApproach?,
    source: String,
    target: String,
    approach: TranslationApproach
) -> TranslationSession.Configuration {
    TranslationBridge.configuration(
        replacing: current,
        builtWith: currentApproach,
        source: source,
        target: target,
        approach: approach
    )
}

@available(macOS 26.0, *)
extension TranslationBridge {
    /// The fastest answer the system can give: low latency answers long text in
    /// a fraction of the default strategy's ~20 seconds.
    static func makeSession(
        source: Locale.Language,
        target: Locale.Language,
        approach: TranslationApproach
    ) -> TranslationSession {
        if #available(macOS 26.4, *) {
            let strategy: TranslationSession.Strategy = approach == .fast ? .lowLatency : .highFidelity
            return TranslationSession(installedSource: source, target: target, preferredStrategy: strategy)
        }
        return TranslationSession(installedSource: source, target: target)
    }

    /// Unlike the view-bound runner, this session outlives the widget, so the
    /// shelf can stay hidden until the result is ready.
    static func translateWithoutView(
        text: String,
        source: Locale.Language,
        target: Locale.Language,
        approach: TranslationApproach,
        onPartial: @Sendable (String) -> Void
    ) async throws -> String {
        let session = makeSession(source: source, target: target, approach: approach)
        // Sentence tokenizing is not a job for the main thread.
        let chunks = await Task.detached(priority: .userInitiated) {
            TextChunker.split(text)
        }.value
        if chunks.count <= 1 {
            return try await session.translate(text).targetText
        }

        let requests = chunks.enumerated().map { index, chunk in
            TranslationSession.Request(sourceText: chunk.text,
                                       clientIdentifier: String(index))
        }
        var shown = ""
        var shownChunkCount = 0
        var results = [String?](repeating: nil, count: chunks.count)
        for try await response in session.translate(batch: requests) {
            guard let id = response.clientIdentifier,
                  let index = Int(id), index < results.count else { continue }
            results[index] = response.targetText

            // Show only an unbroken prefix, in chunk order.
            while shownChunkCount < chunks.count {
                guard let translated = results[shownChunkCount] else { break }
                shown += translated + chunks[shownChunkCount].trailing
                shownChunkCount += 1
            }
            onPartial(shown)
        }

        var full = ""
        for (index, chunk) in chunks.enumerated() {
            full += (results[index] ?? "") + chunk.trailing
        }
        return full
    }
}

@available(macOS 15.0, *)
private struct TranslationRunner: ViewModifier {
    @ObservedObject var model: TranslateModel
    @State private var configuration: TranslationSession.Configuration?
    /// The framework does not expose the strategy a configuration carries, so
    /// the runner remembers it.
    @State private var configurationApproach: TranslationApproach?

    func body(content: Content) -> some View {
        content
            .task(id: model.job?.id) {
                guard let job = model.currentJob(), !job.runsWithoutView else {
                    configuration = nil
                    configurationApproach = nil
                    return
                }
                configuration = nextConfig(
                    configuration,
                    currentApproach: configurationApproach,
                    source: job.source,
                    target: job.target,
                    approach: job.approach ?? .fast
                )
                configurationApproach = job.approach ?? .fast
            }
            .translationTask(configuration) { session in
                // The closure is main-actor isolated, `translate` is not. The
                // session never leaves the closure, so the hand-over is safe.
                nonisolated(unsafe) let session = session
                guard let job = model.currentJob(), !job.runsWithoutView else { return }
                model.translationSessionStarted(jobID: job.id)
                // Sentence tokenizing is not a job for the main thread.
                let chunks = await Task.detached(priority: .userInitiated) {
                    TextChunker.split(job.text)
                }.value
                do {
                    if chunks.count <= 1 {
                        let response = try await session.translate(job.text)
                        model.complete(jobID: job.id, text: response.targetText)
                        return
                    }

                    let requests = chunks.enumerated().map { index, chunk in
                        TranslationSession.Request(sourceText: chunk.text,
                                                   clientIdentifier: String(index))
                    }
                    var shown = ""
                    var shownChunkCount = 0
                    var results = [String?](repeating: nil, count: chunks.count)
                    for try await response in session.translate(batch: requests) {
                        guard let id = response.clientIdentifier,
                              let index = Int(id), index < results.count else { continue }
                        results[index] = response.targetText

                        // Show only an unbroken prefix, in chunk order.
                        while shownChunkCount < chunks.count {
                            guard let translated = results[shownChunkCount] else { break }
                            shown += translated + chunks[shownChunkCount].trailing
                            shownChunkCount += 1
                        }
                        model.partial(jobID: job.id, text: shown)
                    }

                    var full = ""
                    for (i, chunk) in chunks.enumerated() {
                        full += (results[i] ?? "") + chunk.trailing
                    }
                    model.complete(jobID: job.id, text: full)
                } catch {
                    guard !Task.isCancelled else { return }
                    model.translationFailed(jobID: job.id, error: error.localizedDescription)
                }
            }
    }
}

@available(macOS 15.0, *)
private struct TranslationPreparer: ViewModifier {
    @ObservedObject var model: TranslateModel
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.prepare) { _, request in
                guard let request else { return }
                // A fresh configuration every time: an invalidated one cannot
                // ask the system for the download sheet.
                configuration = nextConfig(
                    nil,
                    currentApproach: nil,
                    source: request.source,
                    target: request.target,
                    approach: request.approach
                )
            }
            .translationTask(configuration) { session in
                // Shows the system download sheet. Only ever mounted in the
                // settings pane: a sheet raised from the shelf is drawn under it.
                nonisolated(unsafe) let session = session
                do {
                    try await session.prepareTranslation()
                } catch {
                    model.note("prepare failed: \(error.localizedDescription)")
                }
                await model.finishPrepare()
            }
    }
}

extension View {
    /// Carries out the model's translation jobs with the system's on-device models.
    @ViewBuilder
    func translationRunner(_ model: TranslateModel) -> some View {
        if #available(macOS 15.0, *) {
            modifier(TranslationRunner(model: model))
        } else {
            self
        }
    }

    /// Lets the model ask the system to download a language pair.
    @ViewBuilder
    func translationPreparer(_ model: TranslateModel) -> some View {
        if #available(macOS 15.0, *) {
            modifier(TranslationPreparer(model: model))
        } else {
            self
        }
    }
}

struct TextChunk: Sendable {
    let text: String
    /// Whitespace to put back after the translated text.
    let trailing: String
}

/// Splits text into pieces the engine can answer one at a time, keeping the
/// source's line breaks so the result has the same shape. A line is one piece;
/// a line longer than `maxChars` is split again at sentence and word
/// boundaries, so results can still arrive one by one.
enum TextChunker {
    static let maxChars = 500

    static func split(_ text: String, maxChars: Int = TextChunker.maxChars) -> [TextChunk] {
        guard text.contains(where: \.isNewline) else {
            return splitSentences(text, maxChars: maxChars)
        }
        var chunks: [TextChunk] = []
        // Whitespace since the last line: a newline, or the blank lines
        // between paragraphs. It goes back after the line before it.
        var gap = ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if line.allSatisfy(\.isWhitespace) {
                gap += String(line) + (index < lines.count - 1 ? "\n" : "")
                continue
            }
            if !gap.isEmpty, let previous = chunks.last {
                chunks[chunks.count - 1] = TextChunk(
                    text: previous.text,
                    trailing: previous.trailing + gap
                )
                gap = ""
            }
            chunks.append(contentsOf: splitSentences(String(line), maxChars: maxChars))
            gap = index < lines.count - 1 ? "\n" : ""
        }
        if !gap.isEmpty, let previous = chunks.last {
            chunks[chunks.count - 1] = TextChunk(
                text: previous.text,
                trailing: previous.trailing + gap
            )
        }
        assert(chunks.map { $0.text + $0.trailing }.joined() == text)
        assert(chunks.allSatisfy { !$0.text.isEmpty && $0.text.count <= maxChars })
        return chunks
    }

    /// The line's own text, split at sentence boundaries when it is too long.
    private static func splitSentences(_ text: String, maxChars: Int) -> [TextChunk] {
        guard text.count > maxChars else { return [TextChunk(text: text, trailing: "")] }

        var pieces: [Range<String.Index>] = []
        let sentences = NLTokenizer(unit: .sentence)
        sentences.string = text
        sentences.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if text.distance(from: range.lowerBound, to: range.upperBound) > maxChars {
                let words = NLTokenizer(unit: .word)
                words.string = text
                var lastTokenEnd = range.lowerBound
                func appendSegment(_ segment: Range<String.Index>) {
                    var start = segment.lowerBound
                    while start < segment.upperBound {
                        let end = text.index(start, offsetBy: maxChars, limitedBy: segment.upperBound) ?? segment.upperBound
                        pieces.append(start..<end)
                        start = end
                    }
                }
                words.enumerateTokens(in: range) { wordRange, _ in
                    let segment = lastTokenEnd..<wordRange.upperBound
                    if !segment.isEmpty { appendSegment(segment) }
                    lastTokenEnd = wordRange.upperBound
                    return true
                }
                if lastTokenEnd < range.upperBound { appendSegment(lastTokenEnd..<range.upperBound) }
            } else {
                pieces.append(range)
            }
            return true
        }

        var chunks: [TextChunk] = []
        func append(_ slice: Substring) {
            var body = slice
            var trailing = ""
            while let last = body.last, last.isWhitespace {
                trailing = String(last) + trailing
                body = body.dropLast()
            }
            if body.isEmpty {
                if let previous = chunks.last {
                    chunks[chunks.count - 1] = TextChunk(text: previous.text,
                                                         trailing: previous.trailing + trailing)
                }
            } else {
                chunks.append(TextChunk(text: String(body), trailing: trailing))
            }
        }

        var start = text.startIndex
        var count = 0
        for piece in pieces {
            let length = text.distance(from: piece.lowerBound, to: piece.upperBound)
            if count > 0, count + length > maxChars {
                append(text[start..<piece.lowerBound])
                start = piece.lowerBound
                count = 0
            }
            count += length
        }
        append(text[start...])
        assert(chunks.map { $0.text + $0.trailing }.joined() == text)
        assert(chunks.allSatisfy { !$0.text.isEmpty && $0.text.count <= maxChars })
        return chunks
    }

    /// A line stays one piece and the whitespace between lines comes back
    /// unchanged, blank lines included.
    static func checkLayoutRules() {
        let list = split("• One\n• Two")
        assert(list.count == 2)
        assert(list[0].text == "• One" && list[0].trailing == "\n")
        assert(list[1].text == "• Two" && list[1].trailing == "")
        assert(list.map { $0.text + $0.trailing }.joined() == "• One\n• Two")

        let paragraphs = split("One\n\nTwo")
        assert(paragraphs.count == 2)
        assert(paragraphs[0].trailing == "\n\n")
        assert(paragraphs.map { $0.text + $0.trailing }.joined() == "One\n\nTwo")
    }
}
