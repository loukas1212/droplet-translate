import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import DroppyKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LanguageOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let menuName: String
}

struct TranslationJob: Equatable, Sendable {
    let id = UUID()
    let text: String
    let source: String
    /// `auto` or the language the user chose; `source` is the resolved one.
    let selectedSource: String
    let target: String
    let startedAt: Date
    /// `nil` when a server does the work.
    let approach: TranslationApproach?
    /// Apple's strategy, or the provider's name.
    let engine: String
    /// The shelf can stay away while the result is on its way.
    var runsWithoutView = false
    /// A live translation is not worth a panel.
    var isLive = false
}

struct PrepareRequest: Equatable, Sendable {
    let id = UUID()
    let source: String
    let target: String
    /// The classic models or the Apple Intelligence ones.
    let approach: TranslationApproach
}

enum PairInfo: Equatable {
    case unknown
    case ready
    case needsDownload
    case unsupported

    var canDownload: Bool { self == .needsDownload || self == .unknown }
}

enum CaptureState: Equatable {
    case idle
    case selecting
    case recognizing
}

enum SelectState: Equatable {
    case idle
    case pulling
    case armed
}

/// How the droplet trades speed for fluency. The stored values stay fixed;
/// an older "auto" value is read as Apple Intelligence.
enum TranslationQuality: String, CaseIterable, Identifiable {
    /// The fastest, a little less fluent.
    case fast
    /// More fluent, much slower on long text.
    case accurate

    var id: String { rawValue }

    var approach: TranslationApproach {
        self == .fast ? .fast : .accurate
    }
}

/// One model for the whole droplet: shelf and settings read and write the same
/// state, persisted through `host.preferences`.
@MainActor
final class TranslateModel: ObservableObject {
    static let auto = "auto"
    static let english = "en"

    /// Past this the translation takes minutes, and a shelf is not the place
    /// to wait. Not a setting: it is what the engine can answer.
    static let maxInputLength = 5000

    /// A stored value, preferring the current key over the one the setting
    /// carried before it was renamed.
    private static func stored(
        _ preferences: any DropletPreferencesService,
        key: String,
        legacy: String,
        default defaultValue: String
    ) -> String {
        let current = preferences.value(forKey: key, default: "")
        if !current.isEmpty { return current }
        return preferences.value(forKey: legacy, default: defaultValue)
    }

    private static func normalizedLanguageID(_ id: String) -> String {
        id == auto ? auto : LanguageTools.canonicalID(id)
    }

    enum Status: Equatable {
        case idle
        case translating
        case needsDownload
        case unsupported
        case undetected
        case sameLanguage
        case failed
        case osTooOld
    }

    enum CaptureResultRoute: Equatable {
        case wait
        case shelf
        case selectedDestination
    }

    private enum StatusRecoveryAction: Sendable {
        case download
        case retry
    }

    @Published var input = ""
    @Published private(set) var output = ""
    @Published private(set) var status: Status = .idle
    @Published private(set) var detected: String?
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var selectState: SelectState = .idle
    @Published var isPinned = false
    @Published var isToolbarExpanded = false
    @Published private(set) var languages: [LanguageOption] = LanguageTools.fallback
    /// The languages whose pair with the current target is downloaded, so the
    /// source menu offers only what translates without fetching a model.
    @Published private(set) var installedSourceIDs: Set<String> =
        Set(LanguageTools.fallback.map(\.id))
    /// The same against the current source, for the target menu.
    @Published private(set) var installedTargetIDs: Set<String> =
        Set(LanguageTools.fallback.map(\.id))
    @Published private(set) var job: TranslationJob?
    @Published private(set) var outputScrollResetToken = UUID()
    @Published private(set) var prepare: PrepareRequest?
    @Published private(set) var pairInfo: PairInfo = .unknown
    @Published private(set) var notice: String?
    @Published private(set) var copied = false
    @Published private(set) var canRetryTranslation = false
    /// The panel floats next to the last picked region, so the eye stays put.
    private(set) var lastCaptureRegion: CGRect?
    private(set) var lastCaptureScreen: NSScreen?


    @Published var sourceID: String = TranslateModel.auto {
        didSet { languageChanged(key: "source", value: sourceID) }
    }

    @Published var targetID: String = TranslateModel.english {
        didSet { languageChanged(key: "target", value: targetID) }
    }

    /// Seeds the model behind a settings picture. Every property is set through
    /// its backing storage, so the example never moves the user's settings.
    func beginPreview(
        source: String,
        target: String,
        text: String,
        translated: String,
        page: Page
    ) {
        _sourceID = Published(initialValue: source)
        _targetID = Published(initialValue: target)
        _input = Published(initialValue: text)
        _output = Published(initialValue: translated)
        _resultPage = Published(initialValue: page)
    }

    @Published var liveTranslate = false {
        didSet { persist("live", liveTranslate) }
    }

    @Published var translationQuality: TranslationQuality = .accurate {
        didSet {
            persist("quality", translationQuality.rawValue)
            refreshInstalledLanguages()
        }
    }

    /// Where a finished translation is shown.
    @Published var resultDisplay: ResultDisplay = .normal {
        didSet { persist("resultDisplay", resultDisplay.rawValue) }
    }

    /// The screen edge the side panel docks to.
    @Published var sidePanelSide: SidePanelSide = .right {
        didSet { persist("sidePanelSide", sidePanelSide.rawValue) }
    }

    /// Moves the current result or status to the chosen home and closes the
    /// ones it no longer uses, so one Display mode at a time is on screen.
    func setResultDisplay(_ display: ResultDisplay) {
        guard display != resultDisplay else { return }
        resultDisplay = display
        if display != .panel {
            TranslationPanel.shared.closePanel()
        }
        if hasCompletedResultForCurrentInput {
            presentResultInSelectedDestination()
        } else {
            presentStatusInSelectedDestination()
        }
    }

    /// Apple's on-device models are the default; the others send the text to
    /// a server, and the settings say so.
    @Published var translationProvider: TranslationProvider = .apple {
        didSet {
            persist("provider", translationProvider.rawValue)
            if translationProvider != .apple {
                // Remember the AI provider so switching engines keeps it.
                persist("aiProvider", translationProvider.rawValue)
            }
            // Endpoint and model are stored per provider; only a custom
            // endpoint is the user's to change.
            if oldValue != .apple {
                persist(Self.providerValueKey("baseURL", oldValue), providerBaseURL)
                persist(Self.providerValueKey("model", oldValue), providerModel)
            }
            // A built-in provider knows where it lives.
            providerBaseURL = translationProvider == .custom
                ? storedProviderValue("baseURL", for: translationProvider)
                : translationProvider.defaultBaseURL
            providerModel = storedProviderValue("model", for: translationProvider)
            providerKey = KeychainStore.read(translationProvider.keyAccount) ?? ""
            refreshInstalledLanguages()
        }
    }

    /// The name a provider's own value is kept under.
    private static func providerValueKey(_ name: String, _ provider: TranslationProvider) -> String {
        "\(name).\(provider.rawValue)"
    }

    private func storedProviderValue(_ name: String, for provider: TranslationProvider) -> String {
        let key = Self.providerValueKey(name, provider)
        let stored = host?.preferences.value(forKey: key, default: "") ?? ""
        if !stored.isEmpty { return stored }
        switch name {
        case "baseURL": return provider.defaultBaseURL
        case "model": return provider.defaultModel
        default: return ""
        }
    }

    /// Follows the provider and the models, so there is one truth, not two.
    var translationEngine: TranslationEngine {
        guard translationProvider == .apple else { return .provider }
        return translationQuality == .fast ? .classic : .appleIntelligence
    }

    /// The network engine keeps the last provider, so switching back and forth
    /// does not lose it.
    func setTranslationEngine(_ engine: TranslationEngine) {
        switch engine {
        case .classic:
            translationProvider = .apple
            translationQuality = .fast
        case .appleIntelligence:
            translationProvider = .apple
            translationQuality = .accurate
        case .provider:
            guard translationProvider == .apple else { return }
            let stored = host?.preferences.value(
                forKey: "aiProvider",
                default: TranslationProvider.openAI.rawValue
            ) ?? TranslationProvider.openAI.rawValue
            translationProvider = TranslationProvider(rawValue: stored) ?? .openAI
        }
    }

    @Published var providerBaseURL = "" {
        didSet {
            persist("providerBaseURL", providerBaseURL)
            if translationProvider != .apple {
                persist(Self.providerValueKey("baseURL", translationProvider), providerBaseURL)
            }
        }
    }

    @Published var providerModel = "" {
        didSet {
            persist("providerModel", providerModel)
            if translationProvider != .apple {
                persist(Self.providerValueKey("model", translationProvider), providerModel)
            }
        }
    }

    /// In the keychain, never in preferences; written after typing stops.
    @Published var providerKey = "" {
        didSet { scheduleKeyWrite() }
    }

    @Published private(set) var providerHasKey = false
    @Published private(set) var engineStatus: EngineStatus = .unknown

    enum EngineStatus: Equatable {
        case unknown
        case testing
        case connected
        case failed(String)

        var text: String {
            switch self {
            case .unknown: return L10n.tr("engine.status.unknown")
            case .testing: return L10n.tr("engine.status.testing")
            case .connected: return L10n.tr("engine.status.connected")
            case .failed(let message): return message
            }
        }
    }

    /// A keychain write per keystroke is slow; the key must not be logged.
    private func scheduleKeyWrite() {
        keyWriteTask?.cancel()
        let account = translationProvider.keyAccount
        let key = providerKey
        keyWriteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            self.keyWriteTask = nil
            KeychainStore.write(account, key.isEmpty ? nil : key)
            self.providerHasKey = !key.isEmpty
        }
    }

    func removeProviderKey() {
        providerKey = ""
        KeychainStore.remove(translationProvider.keyAccount)
        providerHasKey = false
    }

    func testEngineConnection() {
        guard translationProvider != .apple else {
            engineStatus = .connected
            return
        }
        engineStatus = .testing
        let configuration = ProviderConfiguration(
            provider: translationProvider,
            baseURL: providerBaseURL,
            model: providerModel,
            apiKey: providerKey
        )
        let target = name(for: targetID)
        Task { [weak self] in
            do {
                _ = try await TranslationEngines.translate(
                    configuration: configuration,
                    request: EngineRequest(text: "Hello", source: "English", target: target),
                    onPartial: { _ in }
                )
                await MainActor.run { self?.engineStatus = .connected }
            } catch {
                await MainActor.run {
                    self?.engineStatus = .failed(error.localizedDescription)
                }
            }
            self?.announceEngineStatus()
        }
    }


    // MARK: The permissions

    struct PermissionState: Identifiable {
        let permission: DropletPermission
        let titleKey: String
        let detailKey: String
        let status: DropletPermissionStatus

        var id: String { permission.rawValue }
    }

    @Published private(set) var permissionStates: [PermissionState] = []

    func refreshPermissions() {
        guard let host else { return }
        permissionStates = [
            PermissionState(
                permission: .accessibility,
                titleKey: "settings.permissions.accessibility",
                detailKey: "settings.permissions.accessibility.sub",
                status: host.permissions.status(for: .accessibility)
            ),
            PermissionState(
                permission: .screenCapture,
                titleKey: "settings.permissions.screenCapture",
                detailKey: "settings.permissions.screenCapture.sub",
                status: host.permissions.status(for: .screenCapture)
            )
        ]
    }

    func requestPermission(_ permission: DropletPermission) async {
        guard let host else { return }
        _ = await host.permissions.request(permission)
        refreshPermissions()
    }

    func openSystemSettings(for permission: DropletPermission) {
        host?.permissions.openSystemSettings(for: permission)
    }

    /// A row that changes while the user is elsewhere on the page is silent to
    /// VoiceOver, so the answer is announced politely, without taking focus.
    private func announceEngineStatus() {
        let message: String
        switch engineStatus {
        case .unknown: return
        case .testing: message = L10n.tr("engine.status.testing")
        case .connected: message = L10n.tr("engine.status.connected")
        case .failed(let detail): message = detail
        }
        AccessibilityNotification.Announcement(message).post()
    }

    /// The host's own cue, so it feels like the rest of Droppy.
    func playSuccessCue() {
        host?.feedback.play(.success)
    }

    /// The shelf is away while the work runs, so Escape belongs to the app
    /// underneath; a global monitor is the only way to hear it.
    private var escapeMonitor: Any?

    private func watchForEscape() {
        stopWatchingForEscape()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                guard let self else { return }
                guard self.job != nil else {
                    self.stopWatchingForEscape()
                    return
                }
                self.cancelCurrentTranslation()
            }
        }
    }

    private func stopWatchingForEscape() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    /// The same path serves Escape and the timeout: the work stops and the
    /// shelf comes back empty.
    func cancelCurrentTranslation() {
        guard job != nil else { return }
        cancelActiveTranslation()
        stopWatchingForEscape()
        jobComesFromCapture = false
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
        capturedInput = nil
        notice = nil
        canRetryTranslation = false
        status = .idle
        revealResultWhenReady()
    }

    /// Whether the running work came from a capture or selection, which is
    /// what Escape and the timeout may cancel.
    private var jobComesFromCapture = false

    @Published var autoCopyResult = false {
        didSet { persist("autoCopy", autoCopyResult) }
    }

    /// The page the user picks for a finished translation: the translation
    /// alone, or the original above it.
    @Published var resultPage: Page = .result {
        // Saved under the old key so a choice made before the rename survives.
        didSet { persist("resultContent", resultPage.rawValue) }
    }

    /// The page the cards are on right now. Words on screen decide it, so a
    /// status never hides a translation the user can still read.
    var page: Page {
        guard output.isEmpty else { return resultPage }
        return status == .idle && notice == nil ? .input : .status
    }

    @Published var uiLanguage = "system" {
        didSet {
            persist("uiLanguage", uiLanguage)
            L10n.override = Self.uiOverride(for: uiLanguage)
        }
    }

    private var host: DropletHost?

    /// The shape the host mounted the shelf in, so settings previews can draw
    /// the same island or camera-notch shell.
    @Published private(set) var shelfUsesIslandCurvature = true
    @Published private(set) var notchCutoutWidth: CGFloat = 200
    @Published private(set) var notchCutoutHeight = DroppyShellMetrics.physicalNotchHeight
    /// The appearance Droppy is drawing its surfaces in. The settings page's
    /// pictures follow it, so a preview never shows a surface the app would
    /// not draw.
    @Published private(set) var surfaceAppearance: DropletSurfaceAppearance = .dark

    /// The scheme that matches the appearance Droppy is drawing its surfaces
    /// in, so a picture in the settings reads the app's own theme.
    var surfaceColorScheme: ColorScheme {
        surfaceAppearance == .dark ? .dark : .light
    }

    func updateShelfPreviewShape(from context: ShelfWidgetContext) {
        switch context.surface {
        case .builtInNotch:
            shelfUsesIslandCurvature = false
        case .dynamicIsland:
            shelfUsesIslandCurvature = true
        case .external:
            shelfUsesIslandCurvature = context.usesIslandCurvature
        @unknown default:
            shelfUsesIslandCurvature = context.usesIslandCurvature
        }
    }

    /// Updates the settings illustration when the host switches between a
    /// hardware notch and its island, or reports new geometry.
    func updateShelfPreviewShape(from geometry: DropletNotchGeometry) {
        shelfUsesIslandCurvature = !geometry.isHardwareNotch
        notchCutoutWidth = geometry.closedWidth
        notchCutoutHeight = geometry.closedHeight
    }

    private var shelfChangeCancellable: AnyCancellable?
    private var environmentChangeCancellable: AnyCancellable?
    private var appActivationObserver: NSObjectProtocol?
    private var lastShelfExpanded: Bool?
    private var translateTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var installedPairs: [String: (status: PairStatus, checkedAt: Date)] = [:]
    private var firstPartialJobID: UUID?
    private var shelfDisappearTask: Task<Void, Never>?
    private var shelfCloseTask: Task<Void, Never>?
    private var capturedInput: String?
    private var lastCompletedLiveKey: LiveTranslationKey?
    private var autoSwitchingTarget = false
    private var loadTask: Task<Void, Never>?
    private var installedScanTask: Task<Void, Never>?
    private var pendingTranslationSuccess: (input: String, action: () -> Void)?
    var ocrTask: Task<String?, Error>?
    private var invalidateCapturedSelectionAction: (() -> Void)?
    private var pinnedShelfSuspended = false
    private var captureShelfDismissalInProgress = false
    private var pendingSelectedDestinationPresentation = false
    private var shelfReopenTask: Task<Void, Never>?
    /// The widget to bring back when a result is ready, set when a capture or
    /// drag selection finishes while the translation is still running.
    private var pendingResultReveal: ShelfWidgetID?
    /// The host does not report this widget's card as expanded, so the view's
    /// own lifecycle is the truth here.
    private var isShelfWidgetVisible = false
    private var isDeactivating = false
    private var shelfWidgetToReveal: ShelfWidgetID?
    private var copyFeedbackTask: Task<Void, Never>?
    private var keyWriteTask: Task<Void, Never>?
    private var translationCache: [TranslationCacheKey: String] = [:]
    private var translationCacheOrder: [TranslationCacheKey] = []

    /// A cached result belongs to its text, pair and engine.
    struct TranslationCacheKey: Hashable {
        let text: String
        let source: String
        let target: String
        /// Two engines word the same sentence differently.
        let engine: String
    }

    /// A repeat of the same text and pair is skipped after the debounce; an
    /// explicit Submit still retranslates.
    private struct LiveTranslationKey: Equatable {
        let text: String
        let sourceSelection: String
        let target: String
    }

    // MARK: Lifecycle

    func attach(host: DropletHost) {
        // Read first, keep the host after: assigning the published values
        // below must not write the defaults back.
        let preferences = host.preferences
        sourceID = Self.normalizedLanguageID(preferences.value(forKey: "source", default: Self.auto))
        targetID = Self.normalizedLanguageID(preferences.value(forKey: "target", default: Self.english))
        liveTranslate = preferences.value(forKey: "live", default: false)
        // "auto" came from a droplet that chose models by text length; its
        // short-text choice was Apple Intelligence.
        translationQuality = TranslationQuality(
            rawValue: preferences.value(forKey: "quality", default: TranslationQuality.accurate.rawValue)
        ) ?? .accurate
        let storedDisplay = preferences.value(forKey: "resultDisplay", default: "")
        // Legacy names: popup is the floating panel; shelf and takeover are normal.
        switch storedDisplay {
        case "popup": resultDisplay = .panel
        case "shelf", "takeover": resultDisplay = .normal
        default: resultDisplay = ResultDisplay(rawValue: storedDisplay) ?? .normal
        }
        sidePanelSide = SidePanelSide(
            rawValue: preferences.value(forKey: "sidePanelSide", default: SidePanelSide.right.rawValue)
        ) ?? .right
        // Saved values from before the rename: "both" was the pair page.
        let storedPage = Self.stored(
            preferences, key: "resultContent", legacy: "popupContent",
            default: Page.result.rawValue
        )
        resultPage = Page(rawValue: storedPage)
            ?? (storedPage == "both" ? .pair : .result)
        autoCopyResult = preferences.value(forKey: "autoCopy", default: false)
        translationProvider = TranslationProvider(
            rawValue: preferences.value(forKey: "provider", default: TranslationProvider.apple.rawValue)
        ) ?? .apple
        // The provider in use, with the flat keys of the first version as the
        // fallback.
        providerBaseURL = preferences.value(
            forKey: Self.providerValueKey("baseURL", translationProvider),
            default: preferences.value(forKey: "providerBaseURL", default: "")
        )
        providerModel = preferences.value(
            forKey: Self.providerValueKey("model", translationProvider),
            default: preferences.value(forKey: "providerModel", default: "")
        )
        if translationProvider != .apple {
            // A provider that was never configured still has its defaults.
            if providerBaseURL.isEmpty {
                providerBaseURL = translationProvider.defaultBaseURL
            }
            if providerModel.isEmpty {
                providerModel = translationProvider.defaultModel
            }
        }
        providerKey = KeychainStore.read(translationProvider.keyAccount) ?? ""
        providerHasKey = !providerKey.isEmpty
        uiLanguage = preferences.value(forKey: "uiLanguage", default: "system")
        L10n.override = Self.uiOverride(for: uiLanguage)
        self.host = host
        updateShelfPreviewShape(from: host.environment.notchGeometry)
        surfaceAppearance = host.environment.surfaceAppearance
        isDeactivating = false
        isPinned = false
        pinnedShelfSuspended = false
        isShelfWidgetVisible = false
        pendingResultReveal = nil
        lastCompletedLiveKey = nil
        autoSwitchingTarget = false
        shelfWidgetToReveal = nil
        captureShelfDismissalInProgress = false
        pendingSelectedDestinationPresentation = false
        rememberShelfState(host)
        shelfChangeCancellable?.cancel()
        shelfChangeCancellable = host.shelf.didChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.shelfDidChange() }
        }
        environmentChangeCancellable?.cancel()
        environmentChangeCancellable = host.environment.didChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let environment = self.host?.environment else { return }
                self.updateShelfPreviewShape(from: environment.notchGeometry)
                self.surfaceAppearance = environment.surfaceAppearance
            }
        }
        // A permission is granted in System Settings, in another app. Without
        // this refresh the page still says "Denied" when the user returns.
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        loadLanguages()
    }

    static func checkPinReleaseRules() {
        assert(shouldReleasePin(isPinned: true, suspended: false, shelfWasExpanded: true, shelfIsClosed: true))
        assert(!shouldReleasePin(isPinned: true, suspended: true, shelfWasExpanded: true, shelfIsClosed: true))
        assert(!shouldReleasePin(isPinned: true, suspended: false, shelfWasExpanded: false, shelfIsClosed: true))
        assert(!shouldReleasePin(isPinned: true, suspended: false, shelfWasExpanded: true, shelfIsClosed: false))
        assert(!shouldReleasePin(isPinned: false, suspended: false, shelfWasExpanded: true, shelfIsClosed: true))
    }

    func teardown() {
        isDeactivating = true
        cancelAll()
        installedScanTask?.cancel()
        installedScanTask = nil
        stopWatchingForEscape()
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
        job = nil
        prepare = nil
        status = .idle
        captureState = .idle
        selectState = .idle
        isPinned = false
        pinnedShelfSuspended = false
        shelfDisappearTask?.cancel()
        shelfDisappearTask = nil
        shelfCloseTask?.cancel()
        shelfCloseTask = nil
        shelfReopenTask?.cancel()
        shelfReopenTask = nil
        captureShelfDismissalInProgress = false
        pendingSelectedDestinationPresentation = false
        isShelfWidgetVisible = false
        shelfReopenTask?.cancel()
        shelfReopenTask = nil
        pendingResultReveal = nil
        lastCompletedLiveKey = nil
        autoSwitchingTarget = false
        shelfWidgetToReveal = nil
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        copied = false
        shelfChangeCancellable?.cancel()
        shelfChangeCancellable = nil
        environmentChangeCancellable?.cancel()
        environmentChangeCancellable = nil
        lastShelfExpanded = nil
        host = nil
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
    }

    // MARK: Translating

    func inputChanged() {
        liveTask?.cancel()
        liveTask = nil
        notice = nil
        canRetryTranslation = false
        if let capturedInput {
            self.capturedInput = nil
            if capturedInput == input { return }
        }
        cancelActiveTranslation()
        notice = nil
        canRetryTranslation = false
        detected = nil
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
        pendingTranslationSuccess = nil
        guard !trimmedInput.isEmpty else {
            output = ""
            detected = nil
            status = .idle
            return
        }
        guard liveTranslate else { return }
        let key = LiveTranslationKey(
            text: trimmedInput,
            sourceSelection: sourceID,
            target: targetID
        )
        liveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self,
                  self.trimmedInput == key.text,
                  self.sourceID == key.sourceSelection,
                  self.targetID == key.target else { return }
            if key == self.lastCompletedLiveKey,
               (self.status == .idle || self.status == .sameLanguage),
               !self.output.isEmpty {
                return
            }
            self.startTranslation(onSuccess: nil, live: true)
        }
    }

    func translate() {
        startTranslation(onSuccess: nil, live: false)
    }

    private func startTranslation(onSuccess: (() -> Void)?, live: Bool) {
        let text = trimmedInput
        if let onSuccess {
            pendingTranslationSuccess = (input: text, action: onSuccess)
        } else if pendingTranslationSuccess?.input != text {
            invalidateCapturedSelectionAction?()
            invalidateCapturedSelectionAction = nil
            pendingTranslationSuccess = nil
        }
        liveTask?.cancel()
        liveTask = nil
        cancelActiveTranslation()
        guard !text.isEmpty else {
            pendingTranslationSuccess = nil
            output = ""
            detected = nil
            status = .idle
            lastCompletedLiveKey = nil
            return
        }
        notice = nil
        canRetryTranslation = false

        let selectedSource = sourceID
        let initialTarget = targetID
        var resolvedTarget = initialTarget

        // Same language would be a no-op. Switch the target if another
        // language is available; otherwise warn.
        if selectedSource != Self.auto, LanguageTools.isSameLanguage(selectedSource, resolvedTarget) {
            if #available(macOS 15.0, *),
               let switched = autoSwitchTarget(from: selectedSource, current: resolvedTarget) {
                resolvedTarget = switched
            } else {
                lastCompletedLiveKey = LiveTranslationKey(
                    text: text,
                    sourceSelection: selectedSource,
                    target: resolvedTarget
                )
                output = text
                status = .sameLanguage
                if let success = pendingTranslationSuccess, success.input == text {
                    success.action()
                    pendingTranslationSuccess = nil
                    invalidateCapturedSelectionAction = nil
                }
                presentResultInSelectedDestination()
                if !live { revealResultWhenReady() }
                return
            }
        }

        guard #available(macOS 15.0, *) else {
            status = .osTooOld
            presentStatusInSelectedDestination()
            revealResultWhenReady()
            return
        }

        status = .translating
        outputScrollResetToken = UUID()
        // The panel is for a finished result, not progress: close the old one
        // instead of replacing it with a spinner. An empty card keeps its
        // face: the grip that starts the translation is on it, and folding
        // the card away would drop the drag.
        if !output.isEmpty {
            TranslationPanel.shared.closePanel()
        }
        let target = resolvedTarget
        let startedAt = Date()

        translateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var currentTarget = target

            // Auto-detect on device, then hand the framework an explicit pair
            // so it never has to ask the user anything.
            let source: String
            if selectedSource == Self.auto {
                let detectionStartedAt = Date()
                let guess = await Task.detached(priority: .userInitiated) {
                    LanguageTools.detect(text)
                }.value
                note("performance detectMs=\(Self.elapsedMilliseconds(since: detectionStartedAt))")
                guard !Task.isCancelled, trimmedInput == text, sourceID == selectedSource else { return }
                guard let guess else {
                    detected = nil
                    status = .undetected
                    presentStatusInSelectedDestination()
                    revealResultWhenReady()
                    return
                }
                let previousDetection = detected
                detected = guess
                if previousDetection != guess {
                    refreshInstalledLanguages()
                }
                source = guess
            } else {
                detected = nil
                source = selectedSource
            }
            guard !Task.isCancelled, trimmedInput == text, sourceID == selectedSource else { return }

            if LanguageTools.isSameLanguage(source, currentTarget) {
                if let switched = autoSwitchTarget(from: source, current: currentTarget) {
                    currentTarget = switched
                } else {
                    lastCompletedLiveKey = LiveTranslationKey(
                        text: text,
                        sourceSelection: selectedSource,
                        target: currentTarget
                    )
                    output = text
                    status = .sameLanguage
                    if !Task.isCancelled, trimmedInput == text,
                       let success = pendingTranslationSuccess, success.input == text {
                        success.action()
                        pendingTranslationSuccess = nil
                        invalidateCapturedSelectionAction = nil
                    }
                    presentResultInSelectedDestination()
                    if !live { revealResultWhenReady() }
                    return
                }
            }
            guard !Task.isCancelled, trimmedInput == text,
                  sourceID == selectedSource, targetID == currentTarget else { return }

            // The approach is decided before the cache: a result belongs to
            // the quality it was made with.
            let approach = translationQuality.approach
            let engine = translationProvider == .apple
                ? "apple.\(approach.rawValue)"
                : "provider.\(translationProvider.rawValue)"
            let cacheKey = TranslationCacheKey(
                text: text,
                source: source,
                target: currentTarget,
                engine: engine
            )
            if let cached = translationCache[cacheKey] {
                guard !Task.isCancelled, trimmedInput == text,
                      sourceID == selectedSource, targetID == currentTarget else { return }
                output = cached
                status = .idle
                job = nil
                lastCompletedLiveKey = LiveTranslationKey(
                    text: text,
                    sourceSelection: selectedSource,
                    target: currentTarget
                )
                if let success = pendingTranslationSuccess, success.input == text {
                    success.action()
                    pendingTranslationSuccess = nil
                    invalidateCapturedSelectionAction = nil
                }
                presentResultInSelectedDestination()
                if !live { revealResultWhenReady() }
                return
            }

            if translationProvider != .apple {
                // A server does the work: no local models or availability.
                startCloudTranslation(
                    text: text,
                    source: source,
                    target: currentTarget,
                    selectedSource: selectedSource,
                    isLive: live
                )
                return
            }

            let pairStartedAt = Date()
            // The models differ per strategy, so check the ones the job uses.
            let pair = await pairStatus(source: source, target: currentTarget, approach: approach)
            note("performance pairStatusMs=\(Self.elapsedMilliseconds(since: pairStartedAt))")
            guard !Task.isCancelled, trimmedInput == text,
                  sourceID == selectedSource, targetID == currentTarget else { return }
            switch pair {
            case .installed:
                note("performance preflightMs=\(Self.elapsedMilliseconds(since: startedAt))")
                let newJob = TranslationJob(
                    text: text,
                    source: source,
                    selectedSource: selectedSource,
                    target: currentTarget,
                    startedAt: Date(),
                    approach: approach,
                    engine: engine,
                    isLive: live
                )
                job = newJob
                startWatchdog(for: newJob.id)
                if Self.canTranslateWithoutView {
                    // The shelf can stay away until the result is ready.
                    var headless = newJob
                    headless.runsWithoutView = true
                    job = headless
                    if #available(macOS 26.0, *) {
                        runTranslationWithoutView(headless)
                    }
                }
            case .needsDownload:
                status = .needsDownload
                presentStatusInSelectedDestination()
                revealResultWhenReady()
            case .unsupported:
                status = .unsupported
                presentStatusInSelectedDestination()
                revealResultWhenReady()
            }
        }
    }

    /// The text leaves the machine, which is why the provider is off by
    /// default and the settings say where it goes.
    private func startCloudTranslation(
        text: String,
        source: String,
        target: String,
        selectedSource: String,
        isLive: Bool
    ) {
        let provider = translationProvider
        let configuration = ProviderConfiguration(
            provider: provider,
            baseURL: providerBaseURL,
            model: providerModel,
            apiKey: providerKey
        )
        let newJob = TranslationJob(
            text: text,
            source: source,
            selectedSource: selectedSource,
            target: target,
            startedAt: Date(),
            approach: nil,
            engine: "provider.\(provider.rawValue)",
            isLive: isLive
        )
        job = newJob
        startWatchdog(for: newJob.id)
        translateTask?.cancel()
        translateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let started = Date()
            do {
                let output = try await TranslationEngines.translate(
                    configuration: configuration,
                    request: EngineRequest(
                        text: text,
                        source: name(for: source),
                        target: name(for: target)
                    ),
                    onPartial: { [weak self] partial in
                        Task { @MainActor in self?.partial(jobID: newJob.id, text: partial) }
                    }
                )
                guard !Task.isCancelled else { return }
                self.note(
                    "performance translationTotalMs=\(Self.elapsedMilliseconds(since: started))"
                )
                self.complete(jobID: newJob.id, text: output)
            } catch {
                guard !Task.isCancelled else { return }
                self.translationFailed(jobID: newJob.id, error: error.localizedDescription)
            }
        }
    }

    static var canTranslateWithoutView: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Runs without a view, so the work continues while the shelf is away.
    @available(macOS 26.0, *)
    private func runTranslationWithoutView(_ job: TranslationJob) {
        translateTask?.cancel()
        translateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await TranslationBridge.translateWithoutView(
                    text: job.text,
                    source: Locale.Language(identifier: job.source),
                    target: Locale.Language(identifier: job.target),
                    approach: job.approach ?? .fast,
                    onPartial: { [weak self] partial in
                        Task { @MainActor in self?.partial(jobID: job.id, text: partial) }
                    }
                )
                guard !Task.isCancelled else { return }
                self.complete(jobID: job.id, text: output)
            } catch {
                guard !Task.isCancelled else { return }
                self.translationFailed(jobID: job.id, error: error.localizedDescription)
            }
        }
    }

    /// Prefer the last target, then the system languages, then English; return
    /// nil when none differs.
    private func autoSwitchTarget(from source: String, current target: String) -> String? {
        guard LanguageTools.isSameLanguage(source, target) else { return target }
        let supported = Set(languages.map(\.id))
        var candidates: [String] = []
        if let previous = lastCompletedLiveKey?.target {
            candidates.append(previous)
        }
        candidates.append(LanguageTools.systemLanguageID())
        candidates.append(contentsOf: Locale.preferredLanguages.dropFirst().map(LanguageTools.canonicalID))
        candidates.append(Self.english)
        guard let newTarget = candidates.first(where: {
            supported.contains($0) && !LanguageTools.isSameLanguage(source, $0)
        }) else { return nil }
        autoSwitchingTarget = true
        targetID = newTarget
        autoSwitchingTarget = false
        note("language: target auto-switched \(source) -> \(newTarget)")
        return newTarget
    }

    func currentJob() -> TranslationJob? { job }

    /// Submit shows only when there is text to translate.
    var canTranslate: Bool { !trimmedInput.isEmpty }

    /// Clears text and result, keeps the languages.
    func clearInput() {
        liveTask?.cancel()
        liveTask = nil
        cancelActiveTranslation()
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction?()
        input = ""
        output = ""
        notice = nil
        canRetryTranslation = false
        outputScrollResetToken = UUID()
        detected = nil
        status = .idle
        copied = false
        lastCompletedLiveKey = nil
        invalidateCapturedSelectionAction = nil
    }

    /// Entry point for Capture and Select: bypasses the live debounce and
    /// reuses the translate path.
    func ingestCaptured(
        _ text: String,
        onSuccess: (() -> Void)? = nil,
        onSelectionInvalidated: (() -> Void)? = nil
    ) {
        ocrTask?.cancel()
        liveTask?.cancel()
        invalidateCapturedSelectionAction?()
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction = onSelectionInvalidated
        // A region can hold more than the engine takes: cut at the limit and
        // say so, because dropping the whole result would be worse.
        let trimmed = text.count > Self.maxInputLength
            ? String(text.prefix(Self.maxInputLength))
            : text
        if trimmed != text {
            showNotice(L10n.tr("input.tooLong"))
        }
        capturedInput = trimmed
        input = trimmed
        // The capture or selection landed; let the user hear that it did.
        playSuccessCue()
        // The work now runs in the background, where Escape can still reach it.
        jobComesFromCapture = true
        watchForEscape()
        startTranslation(onSuccess: onSuccess, live: false)
    }

    func invalidateCapturedSelection() {
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
        pendingTranslationSuccess = nil
    }

    /// Capture overlay lifecycle: selecting while the overlay is up,
    /// recognizing while OCR runs, idle otherwise.
    func captureStarted() {
        captureState = .selecting
    }
    func captureRecognizing() { captureState = .recognizing }
    func captureFinished() {
        captureState = .idle
    }
    func captureCancelled() {
        captureState = .idle
    }
    func captureFailed() {
        captureState = .idle
        status = .failed
        notice = L10n.tr("capture.failed")
        canRetryTranslation = false
        presentStatusInSelectedDestination()
    }

    func selectPulling() {
        selectState = .pulling
    }
    func selectArmed() { selectState = .armed }
    func selectCancelled() {
        selectState = .idle
    }

    func showNotice(_ message: String) {
        notice = message
        note(message)
    }

    var canCapture: Bool {
        guard let host else { return false }
        return host.isGranted(.screenCapture)
            && host.permissions.status(for: .screenCapture) != .unavailable
    }
    var canSelect: Bool {
        guard let host else { return false }
        return host.isGranted(.accessibility)
            && host.permissions.status(for: .accessibility) != .unavailable
    }
    var canPin: Bool { host?.isGranted(.shelfWrite) == true }
    var canPaste: Bool { host?.isGranted(.clipboardRead) == true }
    var canCopy: Bool { host?.isGranted(.clipboardWrite) == true }

    func retryTranslation() { translate() }

    /// The result card's close: drops the pin and asks the host to put the
    /// shelf away. The host closes only a shelf this droplet opened, so a
    /// shelf the user opened by hovering needs the widget revealed first.
    func hideShelf() {
        guard let host else { return }
        isPinned = false
        pinnedShelfSuspended = false
        _ = setShelfHold(false, on: host)
        host.shelf.close()
        if isShelfWidgetVisible || host.shelf.isExpanded {
            _ = host.shelf.open(revealing: host.shelf.soloWidgetID ?? "translate")
            host.shelf.close()
        }
    }

    /// Hides an open shelf for an external interaction and restores its widget
    /// and pin state on every return path.
    func withShelfHidden(_ operation: () async -> Bool) async -> Bool {
        guard let host, !isDeactivating else { return false }
        // The host does not report this widget's card as expanded, so the
        // view's own visibility decides whether a shelf is on screen.
        let wasOpen = host.shelf.isExpanded
            || host.shelf.soloWidgetID != nil
            || isShelfWidgetVisible
        guard !wasOpen || host.isGranted(.shelfWrite) else {
            showNotice(L10n.tr("shelf.unavailable"))
            return false
        }
        let wasPinned = isPinned
        let widgetID = host.shelf.soloWidgetID
        shelfWidgetToReveal = nil
        captureShelfDismissalInProgress = true
        shelfCloseTask?.cancel()
        shelfCloseTask = nil
        if wasPinned || (wasOpen && host.isGranted(.shelfWrite)) {
            pinnedShelfSuspended = true
        }
        defer {
            if !isDeactivating, let activeHost = self.host {
                isPinned = wasPinned
                // Clear the suspension before opening, so a view appearing
                // during open(revealing:) restores its hold rather than being
                // mistaken for one appearing during the close.
                pinnedShelfSuspended = false
                if wasOpen {
                    let reveal = shelfWidgetToReveal ?? widgetID
                    // The host ignores an open while the card is still
                    // closing, so wait for it to leave the screen.
                    var wait = 0
                    while isShelfWidgetVisible, wait < 40, !Task.isCancelled, !isDeactivating {
                        try? await Task.sleep(for: .milliseconds(20))
                        wait += 1
                    }
                    // Readiness is checked after the wait: translation can
                    // finish while the card animates away.
                    let resultRoute = Self.captureResultRoute(
                        display: resultDisplay,
                        status: status,
                        resultReady: hasCompletedResultForCurrentInput,
                        canWaitForTranslation: Self.canTranslateWithoutView
                    )
                    var restored = false
                    if resultRoute != .selectedDestination {
                        if !isShelfWidgetVisible, let reveal {
                            if resultRoute == .wait {
                                // Headless translation: wait for the result.
                                pendingResultReveal = reveal
                            } else {
                                // Shelf is the home for .normal, and for states
                                // that cannot offer recovery.
                                restored = activeHost.shelf.open(revealing: reveal)
                                if !isShelfWidgetVisible {
                                    scheduleShelfReopen(reveal)
                                }
                            }
                        } else {
                            // The card is still on screen, or still animating;
                            // keep asking for the widget so the result has a shelf.
                            restored = true
                            if let reveal {
                                if resultRoute == .wait {
                                    pendingResultReveal = reveal
                                } else {
                                    scheduleShelfReopen(reveal)
                                }
                            }
                        }
                    }
                    if wasPinned {
                        pinnedShelfSuspended = false
                        if restored {
                            if !setShelfHold(true, on: activeHost) { isPinned = false }
                        } else if pendingResultReveal == nil {
                            // Nothing is coming back: the pin has nothing to hold.
                            isPinned = false
                            _ = setShelfHold(false, on: activeHost)
                        }
                        // The shelf comes back with the result; the pin is
                        // restored when the widget appears.
                    } else {
                        // Without a temporary hold the shelf follows the
                        // pointer like any other widget.
                        pinnedShelfSuspended = false
                        if !restored {
                            _ = setShelfHold(false, on: activeHost)
                        }
                    }
                } else if wasPinned {
                    pinnedShelfSuspended = false
                    if !setShelfHold(true, on: activeHost) { isPinned = false }
                }
                shelfWidgetToReveal = nil
                // Clear this last: a shelf that closed during the interaction
                // must not cancel a translation heading to its destination.
                captureShelfDismissalInProgress = false
                let selectedDestinationReady = Self.captureResultRoute(
                    display: resultDisplay,
                    status: status,
                    resultReady: hasCompletedResultForCurrentInput,
                    canWaitForTranslation: false
                ) == .selectedDestination
                if pendingSelectedDestinationPresentation || selectedDestinationReady {
                    pendingSelectedDestinationPresentation = false
                    if hasCompletedResultForCurrentInput {
                        presentResultInSelectedDestination()
                    } else {
                        presentStatusInSelectedDestination()
                    }
                }
            }
        }
        if wasOpen {
            let closeReveal = widgetID ?? "translate"
            // The host only closes a shelf this droplet opened; a shelf the
            // user opened by hovering is refused. Reveal our widget first,
            // then close. A held shelf needs the hold released first.
            _ = setShelfHold(false, on: host)
            host.shelf.close()
            if isShelfWidgetVisible || host.shelf.isExpanded {
                _ = host.shelf.open(revealing: closeReveal)
                host.shelf.close()
            }
            // The interaction starts now and draws over the card, so the first
            // drag reaches the picker while the card slides out underneath.
        }
        guard !Task.isCancelled, !isDeactivating else { return false }
        return await operation()
    }

    func revealAfterShelfHidden(_ widgetID: ShelfWidgetID) {
        shelfWidgetToReveal = widgetID
    }

    /// Holds the shelf open while the widget shows; reverts when the host
    /// refuses, so the glyph never lies.
    func togglePin() {
        isPinned.toggle()
        if isPinned, pinnedShelfSuspended {
            return
        }
        if !isPinned {
            pinnedShelfSuspended = false
        }
        guard let host, host.isGranted(.shelfWrite) else {
            isPinned = false
            showNotice(L10n.tr("shelf.unavailable"))
            return
        }
        if !setShelfHold(isPinned, on: host) {
            note("Pin: host refused hold open")
            isPinned = !isPinned
        } else {
            note(isPinned ? "Pin: enabled" : "Pin: disabled")
        }
    }

    func complete(jobID: UUID, text: String) {
        guard takeJob(jobID) else { return }
        stopWatchingForEscape()
        jobComesFromCapture = false
        let wasLive = job?.isLive ?? false
        if let current = job {
            note("performance translationTotalMs=\(Self.elapsedMilliseconds(since: current.startedAt))")
            cache(text, for: TranslationCacheKey(
                text: current.text,
                source: current.source,
                target: current.target,
                engine: current.engine
            ))
            lastCompletedLiveKey = LiveTranslationKey(
                text: current.text,
                sourceSelection: current.selectedSource,
                target: current.target
            )
        }
        output = text
        status = .idle
        canRetryTranslation = false
        job = nil
        firstPartialJobID = nil
        if let success = pendingTranslationSuccess, trimmedInput == success.input {
            success.action()
        } else if pendingTranslationSuccess != nil {
            invalidateCapturedSelectionAction?()
        }
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction = nil
        capturedInput = nil
        notice = nil
        if autoCopyResult, !text.isEmpty { copyOutput() }
        // The panel waits out a capture dismissal, so the host accepts it.
        if !wasLive {
            presentResultInSelectedDestination()
        }
        // The shelf comes back only with the result, never before it.
        revealResultWhenReady()
    }

    func translationSessionStarted(jobID: UUID) {
        guard let current = job, current.id == jobID else { return }
        note("performance sessionStartMs=\(Self.elapsedMilliseconds(since: current.startedAt))")
    }

    func translationFailed(jobID: UUID, error: String) {
        guard job?.id == jobID else { return }
        host?.log.info("translation failed: \(error)")
        fail(jobID: jobID, message: "translation failed: \(error)")
    }

    /// A finished prefix of a long translation: show it and keep the watchdog
    /// alive, since the engine is still making progress.
    func partial(jobID: UUID, text: String) {
        guard job?.id == jobID, trimmedInput == job?.text else { return }
        if !text.isEmpty, firstPartialJobID != jobID, let current = job {
            firstPartialJobID = jobID
            note("performance firstPartialMs=\(Self.elapsedMilliseconds(since: current.startedAt))")
        }
        output = text
        startWatchdog(for: jobID)
    }

    func fail(jobID: UUID, message: String) {
        let ours = takeJob(jobID)
        if ours {
            stopWatchingForEscape()
            jobComesFromCapture = false
            pendingTranslationSuccess = nil
            invalidateCapturedSelectionAction?()
            invalidateCapturedSelectionAction = nil
            note(message)
            status = .failed
            notice = L10n.tr("status.failed")
            canRetryTranslation = true
            job = nil
            firstPartialJobID = nil
            presentStatusInSelectedDestination()
        }
        // The selected destination shows the failure, or normal mode brings
        // the shelf back with a visible next step.
        revealResultWhenReady()
    }

    /// Closing the shelf stops work that needs the screen, but a running
    /// translation keeps going: the result is there next time.
    func shelfDidDisappear() {
        isShelfWidgetVisible = false
        shelfDisappearTask?.cancel()
        shelfDisappearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.shelfDisappearTask = nil
            guard !self.pinnedShelfSuspended, !self.captureShelfDismissalInProgress else { return }
            guard !self.isPinned else { return }
            if self.captureState != .idle {
                self.ocrTask?.cancel()
                self.ocrTask = nil
                self.captureState = .idle
            }
            // A live translation that has not started yet is dropped; one
            // already running finishes and keeps its result.
            self.liveTask?.cancel()
            self.shelfDisappearTask = nil
        }
    }

    func shelfDidAppear() {
        isShelfWidgetVisible = true
        // A view appearing during dismissal must not re-apply a hold; that is
        // what kept a pinned shelf from collapsing under the overlay.
        guard !pinnedShelfSuspended, !captureShelfDismissalInProgress else { return }
        shelfDisappearTask?.cancel()
        shelfDisappearTask = nil
        shelfCloseTask?.cancel()
        shelfCloseTask = nil
        if isPinned, let host {
            let restored = setShelfHold(true, on: host)
            if !restored {
                note("Pin: could not apply shelf hold after widget appeared")
            }
        }
    }

    private func schedulePinnedShelfCloseCheck() {
        shelfCloseTask?.cancel()
        shelfCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let host = self.host else { return }
            guard Self.shouldReleasePin(
                isPinned: self.isPinned,
                suspended: self.pinnedShelfSuspended,
                shelfWasExpanded: true,
                shelfIsClosed: !host.shelf.isExpanded && host.shelf.soloWidgetID == nil
            ) else {
                self.shelfCloseTask = nil
                return
            }
            self.releasePin(using: host)
            self.shelfCloseTask = nil
            self.shelfDidDisappear()
        }
    }

    private func shelfDidChange() {
        guard let host else { return }
        let wasExpanded = lastShelfExpanded ?? host.shelf.isExpanded
        let expanded = host.shelf.isExpanded
        lastShelfExpanded = expanded
        // Queue on an expanded-to-collapsed transition even if the host is
        // still clearing the widget ID; the delayed check verifies the final
        // closed state.
        guard isPinned, !pinnedShelfSuspended, wasExpanded, !expanded else { return }
        schedulePinnedShelfCloseCheck()
    }

    private func rememberShelfState(_ host: DropletHost) {
        lastShelfExpanded = host.shelf.isExpanded
    }

    private func setShelfHold(_ holdsOpen: Bool, on host: DropletHost) -> Bool {
        let accepted = host.shelf.setHoldsOpen(holdsOpen)
        rememberShelfState(host)
        return accepted
    }

    private func releasePin(using host: DropletHost) {
        isPinned = false
        pinnedShelfSuspended = false
        _ = setShelfHold(false, on: host)
        note("Pin: shelf closed; pin released")
    }

    /// The whole of the pin's behaviour, as a testable function of four
    /// conditions.
    static func shouldReleasePin(
        isPinned: Bool,
        suspended: Bool,
        shelfWasExpanded: Bool,
        shelfIsClosed: Bool
    ) -> Bool {
        isPinned && !suspended && shelfWasExpanded && shelfIsClosed
    }

    /// A capture waits while translation is headless, then uses its selected
    /// destination for a result or a terminal status; normal keeps the shelf.
    static func captureResultRoute(
        display: ResultDisplay,
        status: Status,
        resultReady: Bool,
        canWaitForTranslation: Bool
    ) -> CaptureResultRoute {
        if status == .translating {
            return canWaitForTranslation ? .wait : .shelf
        }
        if display != .normal {
            switch status {
            case .needsDownload, .unsupported, .undetected, .failed, .osTooOld:
                return .selectedDestination
            case .idle, .sameLanguage:
                break
            case .translating:
                break
            }
        }
        if display != .normal && resultReady { return .selectedDestination }
        return .shelf
    }

    private func startWatchdog(for id: UUID) {
        watchdog?.cancel()
        // Classic answers about eight times faster, so the budget follows the
        // models; the cap stops a runaway paste spinning for minutes.
        let text = job?.text.count ?? 0
        let approach = job?.approach ?? .accurate
        let perThousand: Double = approach == .fast ? 2.0 : 6.0
        let floor: Double = approach == .fast ? 15.0 : 30.0
        let limit = min(180.0, max(floor, Double(text) / 1000.0 * perThousand + 15.0))
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if self.jobComesFromCapture {
                // A capture timeout is a cancellation, not an error.
                self.cancelCurrentTranslation()
            } else {
                self.fail(jobID: id, message: "translation timed out")
            }
        }
    }

    private func languageSelectionChanged() {
        guard !autoSwitchingTarget else { return }
        liveTask?.cancel()
        liveTask = nil
        cancelActiveTranslation()
        pendingTranslationSuccess = nil
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
        status = .idle
        // The availability cache is keyed by pair and approach, so only a
        // download invalidates it.
        prefetchLanguagePair()
        if !output.isEmpty { translate() }
    }

    /// Checks the new pair while the user is still in the menu, so the first
    /// translation does not wait for the check.
    private func prefetchLanguagePair() {
        guard translationProvider == .apple else { return }
        let source = preparedSource
        let target = targetID
        let approach = translationQuality.approach
        Task { [weak self] in
            _ = await self?.pairStatus(source: source, target: target, approach: approach)
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Languages

    func name(for id: String) -> String {
        languages.first { $0.id == id }?.name ?? LanguageTools.name(for: id)
    }

    /// The automatic source has no language of its own to trade, so the disc
    /// uses the detected language, or the fallback, to have a pair.
    var canSwap: Bool {
        if sourceID == Self.auto {
            if let detected, !LanguageTools.isSameLanguage(detected, targetID) {
                return true
            }
            return !LanguageTools.isSameLanguage(fallbackSwapLanguage, targetID)
        }
        return !LanguageTools.isSameLanguage(sourceID, targetID)
    }

    /// The first system language that is not the target, then any language
    /// the droplet can translate. Never equals the target.
    private var fallbackSwapLanguage: String {
        let preferred = Locale.preferredLanguages.map(LanguageTools.canonicalID)
        if let language = preferred.first(where: {
            !LanguageTools.isSameLanguage($0, targetID)
        }) {
            return language
        }
        if let language = languages.first(where: {
            !LanguageTools.isSameLanguage($0.id, targetID)
        }) {
            return language.id
        }
        return Self.english
    }

    /// An automatic source takes the text's language; an explicit source can
    /// only swap with a different target.
    private func resolvedSwapTarget() -> String? {
        guard sourceID == Self.auto else {
            return LanguageTools.isSameLanguage(sourceID, targetID) ? nil : sourceID
        }
        if let detected, !LanguageTools.isSameLanguage(detected, targetID) {
            return detected
        }
        if !trimmedInput.isEmpty,
           let found = LanguageTools.detect(trimmedInput),
           !LanguageTools.isSameLanguage(found, targetID) {
            return found
        }
        let fallback = fallbackSwapLanguage
        return LanguageTools.isSameLanguage(fallback, targetID) ? nil : fallback
    }

    @Published private(set) var swapSpins = 0

    /// Exchanges the pair for the settings page. The shelf's disc also turns
    /// the text around; here only the languages change.
    func swapLanguageSelection() {
        guard let newTarget = resolvedSwapTarget() else { return }
        let newSource = targetID
        // The pair changes in one step: half swapped, the two languages are
        // the same one twice, and the model answers by moving the target.
        autoSwitchingTarget = true
        sourceID = newSource
        targetID = newTarget
        autoSwitchingTarget = false
        languageSelectionChanged()
    }

    /// Source becomes target and the translation becomes the new text.
    func swapLanguages() {
        guard let newTarget = resolvedSwapTarget() else { return }
        let newSource = targetID
        let translated = output
        swapSpins += 1

        // Empty output first: the language observers re-translate only when
        // there is a translation on screen, and the swap does it once below.
        output = ""
        outputScrollResetToken = UUID()
        sourceID = newSource
        targetID = newTarget
        if !translated.isEmpty {
            input = translated
            capturedInput = translated
        }
        translate()
    }

    private func loadLanguages() {
        guard #available(macOS 15.0, *) else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let supported = await TranslationBridge.supportedLanguages()
            guard !Task.isCancelled, !supported.isEmpty else { return }
            self?.languages = supported
            self?.refreshInstalledLanguages()
        }
    }

    /// Asks the system which pairs are installed, one language at a time
    /// against the other side of the current pair. Apple's engines download
    /// per pair and strategy; a network provider has the whole list.
    private func refreshInstalledLanguages() {
        installedScanTask?.cancel()
        installedScanTask = nil
        guard translationProvider == .apple else {
            let all = Set(languages.map(\.id))
            installedSourceIDs = all
            installedTargetIDs = all
            return
        }
        guard #available(macOS 15.0, *) else { return }
        let target = targetID
        let source = preparedSource
        let approach = downloadApproach
        let all = languages
        installedScanTask = Task { [weak self] in
            var forTarget: Set<String> = []
            var forSource: Set<String> = []
            for language in all {
                if Task.isCancelled { return }
                if await TranslationBridge.pairStatus(
                    source: language.id,
                    target: target,
                    approach: approach
                ) == .installed {
                    forTarget.insert(language.id)
                }
                if await TranslationBridge.pairStatus(
                    source: source,
                    target: language.id,
                    approach: approach
                ) == .installed {
                    forSource.insert(language.id)
                }
            }
            guard !Task.isCancelled else { return }
            self?.installedSourceIDs = forTarget
            self?.installedTargetIDs = forSource
        }
    }

    // MARK: Offline languages (settings pane)

    /// The source the settings pane downloads: the chosen one, or the system
    /// language when the source is automatic.
    var preparedSource: String {
        sourceID == Self.auto ? (detected ?? LanguageTools.systemLanguageID()) : sourceID
    }

    func refreshPairInfo() async {
        guard #available(macOS 15.0, *) else {
            pairInfo = .unsupported
            return
        }
        let source = preparedSource
        let target = targetID
        if LanguageTools.isSameLanguage(source, target) {
            pairInfo = .ready
            return
        }
        // Keep the old answer until the new one is in: clearing it made the
        // status flash "Checking" on every switch.
        let status = await pairStatus(
            source: source,
            target: target,
            approach: downloadApproach
        ).pairInfo
        guard source == preparedSource, target == targetID else { return }
        pairInfo = status
    }

    func requestDownload() {
        prepare = PrepareRequest(
            source: preparedSource,
            target: targetID,
            approach: downloadApproach
        )
    }

    var downloadApproach: TranslationApproach {
        translationQuality.approach
    }

    /// False when the host granted no shortcuts (older than 1.16, or none
    /// declared). The door stays visible and does nothing, because a row that
    /// disappears between Macs is harder to explain.
    var canOpenShortcuts: Bool {
        host?.isGranted(.globalShortcuts) ?? false
    }

    /// Opens Droppy's Shortcuts page, narrowed to this droplet; the keys are
    /// listed and rebound there, so the droplet keeps no recorder.
    func openShortcuts() {
        host?.workspace.openShortcuts()
    }

    func finishPrepare() async {
        prepare = nil
        installedPairs.removeAll()
        refreshInstalledLanguages()
        await refreshPairInfo()
    }

    // MARK: Presentation

    func rememberCaptureRegion(_ rect: CGRect?, screen: NSScreen?) {
        lastCaptureRegion = rect
        lastCaptureScreen = screen
    }

    private var hasCompletedResultForCurrentInput: Bool {
        guard status == .idle || status == .sameLanguage,
              !output.isEmpty,
              let lastCompletedLiveKey else { return false }
        return lastCompletedLiveKey.text == trimmedInput
            && lastCompletedLiveKey.target == targetID
    }

    /// Opens an empty card where the user chose to see results, with the caret
    /// in it. The shortcut has no surface of its own, so the Display setting
    /// decides which one comes up.
    func openTranslate() {
        guard let host else { return }
        switch resultDisplay {
        case .normal:
            // The host promotes a solo, keyboard-focusable widget on its own.
            _ = host.shelf.open(revealing: "translate")
            host.shelf.requestKeyboardFocus()
        case .panel:
            TranslationPanel.shared.showEmpty(model: self)
        case .sidePanel:
            SidePanel.shared.revealEmpty()
        }
    }

    /// Capture and selection can finish while the shelf animates away; defer
    /// the host request until it is gone instead of losing it.
    ///
    /// Only the chosen Display mode receives the result; the shelf reads the
    /// model itself, so normal has nothing to present.
    private func presentResultInSelectedDestination() {
        guard !output.isEmpty else { return }
        guard !captureShelfDismissalInProgress else {
            pendingSelectedDestinationPresentation = true
            return
        }
        switch resultDisplay {
        case .normal: break
        case .panel: showPanelResult()
        case .sidePanel: showSidePanelResult()
        }
    }

    private func showPanelResult() {
        TranslationPanel.shared.showResult(
            model: self,
            translated: output,
            source: input,
            sourceName: name(for: detected ?? (sourceID == Self.auto ? targetID : sourceID)),
            showsOriginal: resultPage.showsOriginal,
            onCopy: { [weak self] _ in self?.copyOutput() },
            near: lastCaptureRegion,
            on: lastCaptureScreen
        )
    }

    /// The edge panel is the droplet's own card: the result lands in it and the
    /// card opens on it.
    private func showSidePanelResult() {
        SidePanel.shared.revealResult()
    }

    /// Keeps a terminal status in the chosen destination, with a recovery
    /// action when the state permits one.
    private func presentStatusInSelectedDestination() {
        let message: String
        let recoveryAction: StatusRecoveryAction?
        switch status {
        case .needsDownload:
            message = String(
                format: L10n.tr("status.downloadPair"),
                name(for: preparedSource),
                name(for: targetID)
            )
            recoveryAction = .download
        case .unsupported:
            message = String(
                format: L10n.tr("status.unsupportedPair"),
                name(for: preparedSource),
                name(for: targetID)
            )
            recoveryAction = nil
        case .undetected:
            message = L10n.tr("status.undetected")
            recoveryAction = nil
        case .failed:
            message = notice ?? L10n.tr("status.failed")
            recoveryAction = canRetryTranslation ? .retry : nil
        case .osTooOld:
            message = L10n.tr("status.old")
            recoveryAction = nil
        case .idle, .translating, .sameLanguage:
            return
        }

        guard !captureShelfDismissalInProgress else {
            pendingSelectedDestinationPresentation = true
            return
        }
        let actionTitle: String?
        switch recoveryAction {
        case .download: actionTitle = L10n.tr("status.downloadShort")
        case .retry: actionTitle = L10n.tr("retry")
        case nil: actionTitle = nil
        }

        switch resultDisplay {
        case .normal:
            // The shelf draws the status from the model.
            break
        case .panel:
            TranslationPanel.shared.showStatus(
                message: message,
                actionTitle: actionTitle,
                onAction: recoveryAction.map { action in
                    { [weak self] in self?.performStatusRecoveryAction(action) }
                },
                colorScheme: surfaceColorScheme,
                near: lastCaptureRegion,
                on: lastCaptureScreen
            )
        case .sidePanel:
            // The edge panel carries the status in its own result tile, with
            // the download and retry buttons the status deserves.
            SidePanel.shared.revealResult()
        }
    }

    private func performStatusRecoveryAction(_ action: StatusRecoveryAction) {
        switch action {
        case .download:
            openLanguageDownloadSettings()
        case .retry:
            TranslationPanel.shared.closePanel()
            retryTranslation()
        }
    }

    /// Apple's engines download language models per pair; the network
    /// providers have nothing to fetch, so their menus keep every language.
    var canDownloadLanguages: Bool {
        translationProvider == .apple
    }

    /// Opens the droplet's settings from the edge panel's menu.
    func openSettings() {
        host?.workspace.openSettings()
    }

    /// Closes what covers the desktop and opens the page where the system's
    /// language sheet can be seen. Settings opens first: folding the panel
    /// hands the foreground back to the app behind it, and Settings would
    /// follow the panel into the background.
    func openLanguageDownloadSettings() {
        let opened = host?.workspace.openSettingsPage(
            TranslateSettingsPage.translation.rawValue,
            title: L10n.tr("settings.translation")
        ) ?? false
        if !opened {
            host?.workspace.openSettings()
        }
        TranslationPanel.shared.closePanel()
        SidePanel.shared.fold()
    }

    // MARK: Pasteboard

    func pasteInput() {
        guard canPaste else { showNotice(L10n.tr("permission.clipboard")); return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        guard text.count <= Self.maxInputLength else {
            // Keep the existing text: the paste is refused, not half taken.
            showNotice(L10n.tr("input.tooLong"))
            return
        }
        invalidateCapturedSelectionAction?()
        invalidateCapturedSelectionAction = nil
        capturedInput = nil
        input = text
        inputChanged()
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        guard canCopy, let host, host.workspace.copyToPasteboard(output) else {
            showNotice(L10n.tr("permission.clipboard"))
            return
        }
        copied = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            self?.copied = false
        }
    }

    // MARK: Helpers

    private static func uiOverride(for id: String) -> String? { id == "system" ? nil : id }

    private func languageChanged(key: String, value: String) {
        persist(key, value)
        refreshInstalledLanguages()
        languageSelectionChanged()
    }

    private func cancelAll() {
        shelfDisappearTask?.cancel()
        shelfDisappearTask = nil
        translateTask?.cancel()
        watchdog?.cancel()
        liveTask?.cancel()
        copyFeedbackTask?.cancel()
        loadTask?.cancel()
        ocrTask?.cancel()
        ocrTask = nil
        installedPairs.removeAll()
        translateTask = nil
        watchdog = nil
        liveTask = nil
        copyFeedbackTask = nil
        loadTask = nil
    }

    private func cancelActiveTranslation() {
        translateTask?.cancel()
        translateTask = nil
        watchdog?.cancel()
        watchdog = nil
        job = nil
        if status == .translating { status = .idle }
    }

    private func pairStatus(
        source: String,
        target: String,
        approach: TranslationApproach
    ) async -> PairStatus {
        guard #available(macOS 15.0, *) else { return .unsupported }
        let key = "\(source)>\(target)>\(approach.rawValue)"
        if let cached = installedPairs[key], Date().timeIntervalSince(cached.checkedAt) < 600 {
            return cached.status
        }
        let status = await TranslationBridge.pairStatus(
            source: source,
            target: target,
            approach: approach
        )
        if status == .installed {
            installedPairs[key] = (status, Date())
        }
        return status
    }

    private func cache(_ text: String, for key: TranslationCacheKey) {
        translationCache[key] = text
        translationCacheOrder.removeAll { $0 == key }
        translationCacheOrder.append(key)
        if translationCacheOrder.count > 100 {
            translationCache.removeValue(forKey: translationCacheOrder.removeFirst())
        }
    }

    private static func elapsedMilliseconds(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1_000)
    }

    /// Brings the shelf back with the result. A capture or drag selection
    /// leaves it away while the translation runs; the result is why it returns.
    private func revealResultWhenReady() {
        guard let reveal = pendingResultReveal else { return }
        let route = Self.captureResultRoute(
            display: resultDisplay,
            status: status,
            resultReady: hasCompletedResultForCurrentInput,
            canWaitForTranslation: Self.canTranslateWithoutView
        )
        switch route {
        case .wait:
            // Pair availability and translation are still resolving; a
            // terminal state calls here again.
            return
        case .selectedDestination:
            pendingResultReveal = nil
            return
        case .shelf:
            pendingResultReveal = nil
        }
        guard let host else { return }
        // Normal mode uses the shelf as the result and recovery destination.
        guard !isShelfWidgetVisible else { return }
        _ = host.shelf.open(revealing: reveal)
        if !isShelfWidgetVisible {
            scheduleShelfReopen(reveal)
        }
    }

    /// The host brings the shelf back on its own schedule, and the result has
    /// to be on it when that happens, so keep asking until the widget mounts.
    private func scheduleShelfReopen(_ widgetID: ShelfWidgetID) {
        shelfReopenTask?.cancel()
        shelfReopenTask = Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !self.isDeactivating, let host = self.host else { return }
                guard !self.isShelfWidgetVisible else { return }
                _ = host.shelf.open(revealing: widgetID)
            }
        }
    }

    @discardableResult
    private func takeJob(_ id: UUID) -> Bool {
        guard let current = job, current.id == id, trimmedInput == current.text else { return false }
        watchdog?.cancel()
        return true
    }

    func note(_ message: String) {
        host?.log.info(message)
    }

    private func persist<Value: Codable>(_ key: String, _ value: Value) {
        host?.preferences.setValue(value, forKey: key)
    }

    /// Only the settings on the page that offers the reset. Permissions, the
    /// keychain and the interface language are the user's choices about this
    /// Mac, and a reset that signed them out would be the wrong undo.
    func resetTranslationSettings() {
        sourceID = Self.auto
        targetID = Self.english
        setTranslationEngine(.appleIntelligence)
        liveTranslate = false
    }
}
