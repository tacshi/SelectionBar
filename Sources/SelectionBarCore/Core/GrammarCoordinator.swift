import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
public final class GrammarCoordinator {
  public private(set) var shortcutError: String?
  public private(set) var automaticError: String?
  @ObservationIgnored public var onOpenSettings: (() -> Void)?

  @ObservationIgnored private let settingsStore: SelectionBarSettingsStore
  @ObservationIgnored private let access: any GrammarTextAccessing
  @ObservationIgnored private let service: any GrammarChecking
  @ObservationIgnored private let monitor: any GrammarMonitoring
  @ObservationIgnored private let hotKey: any GrammarHotKeyRegistering
  @ObservationIgnored private let windowFactory: (AnyView) -> any GrammarWindowPresenting
  @ObservationIgnored private let underlines: any GrammarUnderlinePresenting
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private var window: (any GrammarWindowPresenting)?
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  @ObservationIgnored private var eventTask: Task<Void, Never>?
  @ObservationIgnored private var captureTask: Task<Void, Never>?
  @ObservationIgnored private var requestTask: Task<Void, Never>?
  @ObservationIgnored private var mutationTask: Task<Void, Never>?
  @ObservationIgnored private var underlineTask: Task<Void, Never>?
  @ObservationIgnored private var underlineLayout: GrammarUnderlineLayout?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var isStopped = false
  @ObservationIgnored private var isPreparingSource = false
  @ObservationIgnored private var expanded = false
  @ObservationIgnored private var configuration: Configuration?
  @ObservationIgnored private var snapshot: GrammarTextSnapshot?
  @ObservationIgnored private var sourceApplication: NSRunningApplication?
  @ObservationIgnored private var sourceBundleID = ""
  @ObservationIgnored private var lastAttempt:
    (snapshot: GrammarTextSnapshot, profile: GrammarWritingProfile)?
  @ObservationIgnored private var lastResult: CachedResult?
  @ObservationIgnored private var dismissedIndicator: GrammarTextSnapshot?
  @ObservationIgnored private var undoRecord: UndoRecord?
  let review = GrammarReviewState()

  private struct Configuration: Equatable {
    let enabled: Bool
    let grammar: GrammarSettings
    let ignored: [String]
    let clipboardApps: [String]
    let language: String
    let availableProviders: [String]
    let providers: SelectionBarProviderSettingsSnapshot
  }

  private struct CachedResult {
    let snapshot: GrammarTextSnapshot
    let result: GrammarCheckResult
    let profile: GrammarWritingProfile
  }

  private struct UndoRecord {
    let before: GrammarTextSnapshot
    let after: GrammarTextSnapshot
    let result: GrammarCheckResult?
    let inverses: [GrammarSuggestion]
    let appliedCount: Int
    let dismissedCount: Int
  }

  public convenience init(settingsStore: SelectionBarSettingsStore) {
    self.init(
      settingsStore: settingsStore, access: GrammarTextAccess(), service: GrammarCheckService(),
      monitor: GrammarMonitor(), hotKey: GrammarHotKey(),
      windowFactory: { GrammarWindowController(content: $0) },
      underlines: GrammarUnderlineOverlay())
  }

  init(
    settingsStore: SelectionBarSettingsStore, access: any GrammarTextAccessing,
    service: any GrammarChecking, monitor: any GrammarMonitoring,
    hotKey: any GrammarHotKeyRegistering,
    windowFactory: @escaping (AnyView) -> any GrammarWindowPresenting,
    underlines: any GrammarUnderlinePresenting,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.settingsStore = settingsStore
    self.access = access
    self.service = service
    self.monitor = monitor
    self.hotKey = hotKey
    self.windowFactory = windowFactory
    self.underlines = underlines
    self.sleep = sleep
    observeSettings()
  }

  private func currentConfiguration() -> Configuration {
    var runtimeSettings = settingsStore.grammar
    // Remembering a panel choice must not restart the monitor or invalidate its session.
    runtimeSettings.manualProfile = GrammarWritingProfile()
    return Configuration(
      enabled: settingsStore.selectionBarEnabled && runtimeSettings.mode != .off,
      grammar: runtimeSettings,
      ignored: settingsStore.selectionBarIgnoredApps.map(\.id),
      clipboardApps: settingsStore.selectionBarClipboardFallbackIncludedApps.map(\.id),
      language: settingsStore.appLanguage.isEmpty
        ? (Bundle.localizedModule.preferredLocalizations.first ?? "en") : settingsStore.appLanguage,
      availableProviders: settingsStore.availableChatProviders().map(\.id),
      providers: SelectionBarProviderSettingsSnapshot(
        openAIModel: settingsStore.openAIModel,
        openAITranslationModel: settingsStore.openAITranslationModel,
        openRouterModel: settingsStore.openRouterModel,
        openRouterTranslationModel: settingsStore.openRouterTranslationModel,
        customLLMProviders: settingsStore.customLLMProviders))
  }

  private func observeSettings() {
    guard !isStopped else { return }
    let next = withObservationTracking {
      currentConfiguration()
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeSettings() }
    }
    guard next != configuration else { return }
    configuration = next
    closeReview()
    lastAttempt = nil
    lastResult = nil
    dismissedIndicator = nil
    automaticError = nil
    monitor.stop()
    shortcutError = hotKey.configure(shortcut: next.enabled ? next.grammar.shortcut : nil) {
      [weak self] in
      self?.checkManually()
    }
    if next.enabled {
      monitor.start(shortcut: next.grammar.shortcut) { [weak self] in self?.handle($0) }
    }
  }

  public func stop() {
    isStopped = true
    closeReview()
    monitor.stop()
    _ = hotKey.configure(shortcut: nil, action: {})
  }

  public func openSettings() {
    closeReview()
    onOpenSettings?()
  }

  func handle(_ event: GrammarMonitorEvent) {
    guard !isStopped else { return }
    if event == .dismiss {
      dismissedIndicator = snapshot ?? lastResult?.snapshot
      closeReview()
      return
    }
    if isPreparingSource { return }
    var event = event
    if case .click(let point) = event {
      if review.phase == .ready, let id = underlineLayout?.mark(at: point) {
        revealSuggestion(id)
        return
      }
      event = .input
    }
    // Scrolling, moving, and resizing shift the text under the overlay.
    scheduleUnderlineRefresh()
    if review.phase == .applying {
      if event == .changed { return }
      if event == .input {
        markStale()
        return
      }
      if let snapshot, status(of: snapshot) == .differentContext { closeReview() }
      return
    }
    if event == .input {
      // Global key/mouse notifications precede the editor updating its AX value and caret.
      eventTask?.cancel()
      eventTask = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
        self?.inspectSource()
      }
    } else {
      inspectSource()
    }
  }

  private func inspectSource() {
    guard !isStopped, let config = configuration, config.enabled else { return }
    if let snapshot {
      switch status(of: snapshot) {
      case .differentContext:
        closeReview()
        return
      case .changed:
        if expanded {
          markStale()
          return
        }
        closeReview()
      case .current:
        if expanded { return }
      }
    } else if expanded {
      if window?.isKey != true, let sourceApplication,
        NSWorkspace.shared.frontmostApplication?.processIdentifier
          != sourceApplication.processIdentifier
      {
        closeReview()
      }
      return
    }
    guard config.grammar.mode == .automatic else { return }
    debounceTask?.cancel()
    let revision = generation
    debounceTask = Task { [weak self, sleep] in
      do { try await sleep(.milliseconds(1200)) } catch { return }
      guard let self, !Task.isCancelled, self.generation == revision else { return }
      self.beginCapture(manual: false)
    }
  }

  func checkManually() {
    guard configuration?.enabled == true, !isStopped, review.phase != .applying else { return }
    if let snapshot, status(of: snapshot) == .current {
      if window?.isKey == true {
        openReview()
        return
      }
      if let captured = try? access.capture(preferSelection: true),
        captured.hasSameContent(as: snapshot),
        review.profile == settingsStore.grammar.manualProfile,
        review.phase == .ready || review.phase == .completed || review.phase == .checking
      {
        self.snapshot = captured
        openReview()
        return
      }
    }
    dismissedIndicator = nil
    beginCapture(manual: true)
  }

  func recheck() { beginCapture(manual: true, preserveProfile: true, restoringSource: true) }

  private func beginCapture(
    manual: Bool, preserveProfile: Bool = false, restoringSource: Bool = false
  ) {
    guard let config = configuration, config.enabled, !isStopped, review.phase != .applying else {
      return
    }
    let previousSource = snapshot
    let needsRestore = restoringSource || window?.isKey == true
    if !needsRestore {
      sourceApplication = NSWorkspace.shared.frontmostApplication
      sourceBundleID = sourceApplication?.bundleIdentifier ?? ""
    }
    guard !config.ignored.contains(sourceBundleID),
      manual || !config.grammar.excludedApps.contains(where: { $0.id == sourceBundleID })
    else {
      closeReview()
      return
    }
    cancelWork()
    clearUndo()
    review.phase = .checking
    review.failure = nil
    if !preserveProfile {
      review.profile = manual ? settingsStore.grammar.manualProfile : GrammarWritingProfile()
    }
    expanded = manual
    let revision = generation
    let profile = review.profile
    let fallbackPoint = NSEvent.mouseLocation
    captureTask = Task { [weak self] in
      guard let self else { return }
      do {
        self.isPreparingSource = true
        defer { if self.generation == revision { self.isPreparingSource = false } }
        if needsRestore {
          if let previousSource {
            try await self.access.prepareSource(previousSource, requireUnchanged: false)
          } else if let app = self.sourceApplication {
            if GrammarWindowController.ownsKeyboardFocus { NSApp.keyWindow?.resignKey() }
            app.activate(options: [])
            try await Task.sleep(for: .milliseconds(50))
            guard
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            else {
              throw GrammarCheckError.changed
            }
          }
        }
        try Task.checkCancellation()
        let captured: GrammarTextSnapshot
        do {
          captured = try self.access.capture(preferSelection: manual)
        } catch let error as GrammarCheckError
          where (error == .unavailable || error == .empty)
          && manual && config.clipboardApps.contains(self.sourceBundleID)
        {
          captured = try await self.access.captureClipboardSelection()
        }
        guard !Task.isCancelled, revision == self.generation, self.currentConfiguration() == config
        else { return }
        guard !config.ignored.contains(captured.bundleID),
          manual || !config.grammar.excludedApps.contains(where: { $0.id == captured.bundleID })
        else {
          self.closeReview()
          return
        }
        self.sourceBundleID = captured.bundleID
        self.sourceApplication = NSRunningApplication(processIdentifier: captured.processID)
        self.snapshot = captured
        self.review.originalText = captured.text
        self.review.sourceCanApply = captured.canApply
        self.review.appliedCount = 0
        self.review.dismissedCount = 0
        if !manual, let last = self.lastResult, last.profile == profile,
          captured.hasSameContent(as: last.snapshot)
        {
          self.review.result = last.result
          self.review.phase = .ready
          self.showIndicator()
          self.refreshUnderlines()
          return
        }
        if !manual, let attempted = self.lastAttempt, attempted.profile == profile,
          captured.hasSameContent(as: attempted.snapshot)
        {
          self.review.result = nil
          self.review.phase = .ready
          return
        }
        self.review.result = nil
        self.review.focus = nil
        if manual { self.presentReview(at: captured.anchor, takeFocus: true) }
        self.runCheck(captured, profile: profile, automatic: !manual)
      } catch {
        guard !Task.isCancelled, revision == self.generation else { return }
        if manual {
          self.fail(error, captureFailure: true)
          self.presentReview(at: previousSource?.anchor ?? fallbackPoint, takeFocus: true)
        }
      }
    }
  }

  func changeProfile(_ profile: GrammarWritingProfile) {
    guard profile != review.profile, review.phase != .applying else { return }
    review.profile = profile
    settingsStore.grammar.manualProfile = profile
    clearUndo()
    guard let snapshot else {
      recheck()
      return
    }
    guard status(of: snapshot) == .current else {
      markStale()
      return
    }
    cancelWork()
    review.appliedCount = 0
    review.dismissedCount = 0
    runCheck(snapshot, profile: profile, automatic: false)
  }

  private func runCheck(
    _ captured: GrammarTextSnapshot, profile: GrammarWritingProfile, automatic: Bool
  ) {
    guard let config = configuration else { return }
    review.phase = .checking
    review.failure = nil
    let revision = generation
    let previous = requestTask
    previous?.cancel()
    requestTask = Task { [weak self] in
      await previous?.value
      guard let self, !Task.isCancelled, revision == self.generation else { return }
      do {
        guard config.availableProviders.contains(config.grammar.providerID) else {
          throw GrammarCheckError.providerMissing
        }
        let result = try await self.service.check(
          text: captured.text, profile: profile,
          settings: config.grammar, language: config.language, providers: config.providers)
        guard !Task.isCancelled, self.generation == revision, self.currentConfiguration() == config
        else { return }
        switch self.status(of: captured) {
        case .differentContext:
          self.closeReview()
          return
        case .changed:
          if self.expanded { self.markStale() } else { self.closeReview() }
          return
        case .current: break
        }
        self.review.result = result
        self.review.previewOriginalText = captured.text
        self.review.phase = .ready
        self.review.failure = nil
        self.review.sourceCanApply = captured.canApply
        self.automaticError = nil
        self.lastAttempt = (captured, profile)
        self.lastResult = CachedResult(snapshot: captured, result: result, profile: profile)
        if !self.expanded, automatic {
          self.showIndicator()
        }
        self.refreshUnderlines()
      } catch {
        guard !Task.isCancelled, self.generation == revision else { return }
        self.lastAttempt = (captured, profile)
        self.fail(error)
        if !self.expanded { self.automaticError = self.review.failure?.message }
      }
    }
  }

  func retry() {
    guard let snapshot, status(of: snapshot) == .current else {
      recheck()
      return
    }
    cancelWork()
    clearUndo()
    runCheck(snapshot, profile: review.profile, automatic: false)
  }

  func enableClipboardFallback() {
    guard !sourceBundleID.isEmpty, configuration?.ignored.contains(sourceBundleID) == false else {
      return
    }
    if !settingsStore.selectionBarClipboardFallbackIncludedApps.contains(where: {
      $0.id == sourceBundleID
    }) {
      settingsStore.selectionBarClipboardFallbackIncludedApps.append(
        IgnoredApp(id: sourceBundleID, name: sourceApplication?.localizedName ?? sourceBundleID))
    }
    // This explicit recovery updates the shared list without tearing down the review.
    configuration = currentConfiguration()
    recheck()
  }

  func accept(_ suggestions: [GrammarSuggestion]) {
    let pending = Set(review.suggestions.map(\.id))
    guard suggestions.allSatisfy({ pending.contains($0.id) }) else { return }
    applyEdits(suggestions)
  }

  func applyAll() {
    guard let source = snapshot else { return }
    switch review.result {
    case .suggestions(let suggestions): accept(suggestions)
    case .rewrite(let text):
      applyEdits([
        GrammarSuggestion(
          id: UUID(), original: source.text, replacement: text,
          category: .clarity, explanation: "",
          range: NSRange(location: 0, length: source.text.utf16.count))
      ])
    case nil: break
    }
  }

  private func applyEdits(_ edits: [GrammarSuggestion]) {
    guard let source = snapshot, review.canApply, !edits.isEmpty else { return }
    guard status(of: source) == .current else {
      markStale()
      return
    }
    let oldResult = review.result
    let oldApplied = review.appliedCount
    let oldDismissed = review.dismissedCount
    let removedIndex = review.suggestions.firstIndex(where: { edits.contains($0) }) ?? 0
    let restorePanelFocus = window?.isKey == true
    cancelWork()
    clearUndo()
    review.phase = .applying
    hideUnderlines()
    let revision = generation
    mutationTask = Task { [weak self] in
      guard let self else { return }
      var current = source
      var inverses: [GrammarSuggestion] = []
      do {
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
          try Task.checkCancellation()
          guard self.generation == revision else { return }
          current = try await self.access.apply(edit, to: current)
          guard !Task.isCancelled, self.generation == revision else { return }
          inverses.append(
            GrammarSuggestion(
              id: UUID(), original: edit.replacement, replacement: edit.original,
              category: edit.category, explanation: "",
              range: NSRange(location: edit.range.location, length: edit.replacement.utf16.count)))
          if case .suggestions = self.review.result {
            let delta = edit.replacement.utf16.count - edit.range.length
            self.review.suggestions.removeAll { $0.id == edit.id }
            for index in self.review.suggestions.indices
            where self.review.suggestions[index].range.location > edit.range.location {
              self.review.suggestions[index].range.location += delta
            }
          }
          self.snapshot = current
          self.review.originalText = current.text
          self.review.appliedCount += 1
        }
        self.undoRecord = UndoRecord(
          before: source, after: current, result: oldResult,
          inverses: inverses.reversed(), appliedCount: oldApplied, dismissedCount: oldDismissed)
        self.review.hasUndo = true
        self.review.phase = self.review.hasChanges ? .ready : .completed
        self.cacheResult()
        self.refreshUnderlines()
        self.moveFocus(afterRemovingAt: removedIndex)
        if restorePanelFocus { self.window?.focus() }
      } catch {
        guard self.generation == revision else { return }
        self.clearUndo()
        self.review.sourceCanApply = false
        self.fail(error, applicationFailure: true)
        self.lastResult = nil
        if restorePanelFocus, self.status(of: current) != .differentContext { self.window?.focus() }
      }
    }
  }

  func undo() {
    guard let record = undoRecord, review.canUndo else { return }
    guard status(of: record.after) == .current else {
      markStale()
      return
    }
    let restorePanelFocus = window?.isKey == true
    cancelWork()
    review.phase = .applying
    hideUnderlines()
    let revision = generation
    mutationTask = Task { [weak self] in
      guard let self else { return }
      var current = record.after
      do {
        for inverse in record.inverses {
          try Task.checkCancellation()
          current = try await self.access.apply(inverse, to: current)
          guard self.generation == revision else { return }
          self.snapshot = current
        }
        guard GrammarText.identical(current.fullText, record.before.fullText),
          GrammarText.identical(current.text, record.before.text)
        else { throw GrammarCheckError.applyFailed }
        self.review.originalText = current.text
        self.review.result = record.result
        self.review.appliedCount = record.appliedCount
        self.review.dismissedCount = record.dismissedCount
        self.review.phase = .ready
        self.review.sourceCanApply = current.canApply
        self.clearUndo()
        self.cacheResult()
        self.refreshUnderlines()
        self.moveFocus(afterRemovingAt: 0)
        if restorePanelFocus { self.window?.focus() }
      } catch {
        guard self.generation == revision else { return }
        self.clearUndo()
        self.review.sourceCanApply = false
        self.fail(error, applicationFailure: true)
        if restorePanelFocus, self.status(of: current) != .differentContext { self.window?.focus() }
      }
    }
  }

  func dismissSuggestion(_ suggestion: GrammarSuggestion) {
    guard review.phase == .ready,
      let index = review.suggestions.firstIndex(where: { $0.id == suggestion.id })
    else { return }
    review.suggestions.remove(at: index)
    review.dismissedCount += 1
    review.phase = review.hasChanges ? .ready : .completed
    cacheResult()
    refreshUnderlines()
    moveFocus(afterRemovingAt: index)
  }

  private func moveFocus(afterRemovingAt index: Int) {
    let remaining = review.suggestions
    review.requestFocus(
      remaining.isEmpty ? .footer : .suggestion(remaining[min(index, remaining.count - 1)].id))
  }

  private func cacheResult() {
    guard let snapshot, let result = review.result else { return }
    lastResult = CachedResult(snapshot: snapshot, result: result, profile: review.profile)
    lastAttempt = (snapshot, review.profile)
  }

  private func status(of source: GrammarTextSnapshot) -> GrammarSourceStatus {
    access.sourceStatus(source, allowPanelFocus: window?.isKey == true)
  }

  private func markStale() {
    cancelWork()
    hideUnderlines()
    if expanded {
      review.phase = .stale
      review.failure = nil
    } else {
      closeReview()
    }
  }

  private func fail(_ error: Error, captureFailure: Bool = false, applicationFailure: Bool = false)
  {
    let grammarError = error as? GrammarCheckError
    let providerConfigurationIssue: Bool
    switch error as? SelectionBarError {
    case .providerUnavailable: providerConfigurationIssue = true
    case .httpError(let status, _):
      providerConfigurationIssue = [400, 401, 403, 404].contains(status)
    default: providerConfigurationIssue = false
    }
    let recovery: GrammarRecoveryAction
    let message: String
    if applicationFailure {
      message = String(
        localized: "Some changes may have been applied. Check the source text, then recheck.",
        bundle: .localizedModule)
      recovery = .retry
    } else if grammarError == .providerMissing || providerConfigurationIssue {
      message =
        grammarError?.localizedDescription
        ?? String(
          localized: "Check the provider, model, and API key in Settings.", bundle: .localizedModule
        )
      recovery = .settings
    } else if captureFailure, grammarError == .empty || grammarError == .unavailable,
      !sourceBundleID.isEmpty, configuration?.clipboardApps.contains(sourceBundleID) == false
    {
      message = String(
        localized:
          "Could not read this app’s selection. You can enable clipboard fallback for manual checks.",
        bundle: .localizedModule)
      recovery = .clipboard
    } else {
      message =
        grammarError?.localizedDescription
        ?? String(
          localized: "Grammar check failed. Check your provider and connection, then try again.",
          bundle: .localizedModule)
      recovery = .retry
    }
    review.phase = .failed
    review.failure = GrammarReviewFailure(message: message, recovery: recovery)
    hideUnderlines()
  }

  func openReview() {
    expanded = true
    if let snapshot, status(of: snapshot) == .changed { markStale() }
    presentReview(at: snapshot?.anchor ?? NSEvent.mouseLocation, takeFocus: true)
  }

  /// Opens the review at one suggestion without taking keyboard focus from the editor.
  private func revealSuggestion(_ id: UUID) {
    expanded = true
    highlight(id)
    presentReview(at: snapshot?.anchor ?? NSEvent.mouseLocation, takeFocus: false)
  }

  private func highlight(_ id: UUID?) {
    review.highlighted = id
    underlines.highlight(id)
  }

  private func scheduleUnderlineRefresh() {
    guard underlineLayout != nil else { return }
    underlineTask?.cancel()
    // Editors update their geometry after the event; scrolling can keep moving it briefly.
    underlineTask = Task { [weak self] in
      for delay in [40, 260] {
        do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
        self?.refreshUnderlines()
      }
    }
  }

  private func refreshUnderlines() {
    guard configuration?.grammar.showsUnderlines == true, let snapshot,
      review.phase == .ready || review.phase == .checking,
      case .suggestions(let suggestions) = review.result, !suggestions.isEmpty,
      dismissedIndicator.map({ !snapshot.hasSameContent(as: $0) }) ?? true,
      status(of: snapshot) == .current,
      let layout = access.underlineLayout(for: suggestions, in: snapshot), !layout.marks.isEmpty
    else {
      hideUnderlines()
      return
    }
    underlineLayout = layout
    underlines.show(layout, highlighted: review.highlighted)
  }

  private func hideUnderlines() {
    underlineTask?.cancel()
    underlineLayout = nil
    underlines.hide()
  }

  private func showIndicator() {
    guard let snapshot, review.hasChanges,
      dismissedIndicator.map({ !snapshot.hasSameContent(as: $0) }) ?? true
    else { return }
    let content = AnyView(
      GrammarIndicatorView(count: max(1, review.suggestions.count)) { [weak self] in
        self?.openReview()
      })
    present(content, at: snapshot.anchor, interactive: false, takeFocus: false)
  }

  private func presentReview(at point: NSPoint, takeFocus: Bool) {
    let content = AnyView(
      GrammarReviewView(
        state: review,
        profileChanged: { [weak self] in self?.changeProfile($0) },
        accept: { [weak self] in self?.accept([$0]) },
        dismiss: { [weak self] in self?.dismissSuggestion($0) },
        applyAll: { [weak self] in self?.applyAll() },
        undo: { [weak self] in self?.undo() },
        copy: { [weak self] in
          guard let text = self?.review.outputText else { return }
          SelectionBarClipboardService().copyToClipboard(text)
        },
        retry: { [weak self] in
          guard let self else { return }
          if self.review.sourceCanApply == false && self.review.result != nil {
            self.recheck()
          } else {
            self.retry()
          }
        },
        recheck: { [weak self] in self?.recheck() },
        settings: { [weak self] in self?.openSettings() },
        enableClipboard: { [weak self] in self?.enableClipboardFallback() },
        close: { [weak self] in self?.handle(.dismiss) },
        highlight: { [weak self] in self?.highlight($0) },
        resize: { [weak self] in
          Task { @MainActor [weak self] in
            await Task.yield()
            self?.window?.resizeToFit()
          }
        }))
    present(content, at: point, interactive: true, takeFocus: takeFocus)
  }

  private func present(_ content: AnyView, at point: NSPoint, interactive: Bool, takeFocus: Bool) {
    if let window {
      window.update(content: content, interactive: interactive)
    } else {
      let created = windowFactory(content)
      created.onDismiss = { [weak self] in self?.handle(.dismiss) }
      created.update(content: content, interactive: interactive)
      created.showNear(point: point)
      window = created
    }
    if takeFocus { window?.focus() }
  }

  private func clearUndo() {
    undoRecord = nil
    review.hasUndo = false
  }

  private func cancelWork() {
    generation += 1
    isPreparingSource = false
    debounceTask?.cancel()
    eventTask?.cancel()
    captureTask?.cancel()
    requestTask?.cancel()
    mutationTask?.cancel()
  }

  private func closeReview() {
    cancelWork()
    isPreparingSource = false
    expanded = false
    snapshot = nil
    clearUndo()
    review.result = nil
    review.failure = nil
    review.phase = .ready
    review.highlighted = nil
    hideUnderlines()
    window?.dismiss()
    window = nil
  }
}
