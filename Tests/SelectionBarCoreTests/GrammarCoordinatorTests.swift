import AppKit
import SwiftUI
import Testing

@testable import SelectionBarCore

@Suite("Grammar coordination")
@MainActor
struct GrammarCoordinatorTests {
  @Test("The grammar panel keeps its position across results, dismissal, and acceptance")
  func panelPosition() async throws {
    let fixture = GrammarFixture(mode: .hotkey, suspended: true)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.windows.last != nil }
    fixture.windows.last?.topLeft = NSPoint(x: 300, y: 600)
    let initialOrigin = try #require(fixture.windows.last?.topLeft)
    await eventually { await fixture.service.calls.count == 1 }
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    #expect(fixture.windows.last?.topLeft == initialOrigin)

    fixture.coordinator.dismissSuggestion(fixture.coordinator.review.suggestions[0])
    #expect(fixture.windows.last?.topLeft == initialOrigin)

    fixture.coordinator.accept(fixture.coordinator.review.suggestions)
    await eventually { fixture.coordinator.review.phase != .applying }
    #expect(fixture.windows.last?.topLeft == initialOrigin)
  }

  @Test(
    "Automatic activity is debounced, unchanged text is skipped, and dismissal survives activity")
  func automaticDeduplication() async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    fixture.coordinator.handle(.input)
    fixture.coordinator.handle(.input)
    await eventually { await fixture.service.calls.count == 1 }
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    #expect(fixture.access.preferredSelections == [false])
    fixture.coordinator.dismissSuggestion(fixture.coordinator.review.suggestions[0])
    fixture.coordinator.handle(.changed)
    await eventually { fixture.access.preferredSelections.count == 2 }
    #expect(await fixture.service.calls.count == 1)
    #expect(fixture.coordinator.review.suggestions.count == 1)
    fixture.access.changeText("They is ready.")
    fixture.coordinator.handle(.input)
    await eventually { await fixture.service.calls.count == 2 }
  }

  @Test("Manual checking prefers selection and works in apps excluded only from automatic checking")
  func manualAndExclusions() async throws {
    let fixture = GrammarFixture(mode: .automatic, excludeAutomatic: true)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { !fixture.access.preferredSelections.isEmpty }
    #expect(await fixture.service.calls.isEmpty)
    fixture.coordinator.checkManually()
    await eventually { await fixture.service.calls.count == 1 }
    #expect(fixture.access.preferredSelections.last == true)
    fixture.store.selectionBarIgnoredApps = [IgnoredApp(id: "grammar.test", name: "Ignored")]
    await Task.yield()
    await Task.yield()
    fixture.coordinator.checkManually()
    await eventually { fixture.access.preferredSelections.count >= 3 }
    #expect(await fixture.service.calls.count == 1)
  }

  @Test("Stale completions are discarded and only one completion runs at once")
  func staleCompletions() async throws {
    let fixture = GrammarFixture(mode: .hotkey, suspended: true)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { await fixture.service.calls.count == 1 }
    fixture.access.changeText("They is ready.")
    fixture.coordinator.handle(.input)
    fixture.coordinator.checkManually()
    await fixture.service.finish()
    await eventually { await fixture.service.calls.count == 2 }
    #expect(fixture.coordinator.review.suggestions.isEmpty)
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.phase != .checking }
    #expect(fixture.coordinator.review.suggestions.count == 1)
    #expect(await fixture.service.maximumActive == 1)
  }

  @Test("Apply All uses descending ranges and retains dismissed changes")
  func application() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    fixture.coordinator.accept(fixture.coordinator.review.suggestions)
    await eventually { fixture.coordinator.review.phase != .applying }
    #expect(fixture.access.appliedOriginals == ["They is", "He are"])
    #expect(fixture.access.current.text == "He is here. They are ready.")
    #expect(fixture.coordinator.review.suggestions.isEmpty)

    fixture.access.changeText("He are here. They is ready.")
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    fixture.coordinator.dismissSuggestion(fixture.coordinator.review.suggestions[1])
    fixture.coordinator.accept(fixture.coordinator.review.suggestions)
    await eventually { fixture.coordinator.review.phase != .applying }
    #expect(fixture.access.current.text == "He is here. They is ready.")
  }

  @Test("Unchanged source notifications reuse the completed automatic check")
  func cancelledUnchangedText() async throws {
    let fixture = GrammarFixture(mode: .automatic, suspended: true)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { await fixture.service.calls.count == 1 }
    fixture.coordinator.handle(.changed)
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    #expect(await fixture.service.calls.count == 1)
  }

  @Test(
    "Clipboard capture requires an explicit manual request and an opted-in app",
    arguments: [GrammarCheckError.unavailable, .empty])
  func clipboardFallback(captureError: GrammarCheckError) async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.access.captureError = captureError
    let currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
    fixture.store.selectionBarClipboardFallbackIncludedApps = [
      IgnoredApp(id: currentApp, name: "Test")
    ]
    await Task.yield()
    await Task.yield()
    fixture.coordinator.handle(.input)
    await eventually { !fixture.access.preferredSelections.isEmpty }
    #expect(fixture.access.clipboardCaptures == 0)
    fixture.coordinator.checkManually()
    await eventually { fixture.access.clipboardCaptures == 1 }
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    #expect(!fixture.coordinator.review.canApply)

    fixture.access.captureError = .composition
    fixture.coordinator.recheck()
    await eventually { fixture.coordinator.review.failure?.message != nil }
    #expect(fixture.access.clipboardCaptures == 1)
    #expect(
      fixture.coordinator.review.failure?.message
        == GrammarCheckError.composition.localizedDescription)
  }

  @Test("Source changes prevent edits; missing notifications produce a useful error")
  func changedSource() async throws {
    let fixture = GrammarFixture(mode: .hotkey, suspended: true)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { await fixture.service.calls.count == 1 }
    fixture.access.changeText("Changed outside the monitor")
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.phase != .checking }
    #expect(fixture.coordinator.review.phase == .stale)
    #expect(fixture.access.appliedOriginals.isEmpty)
  }

  @Test(
    "Empty and unavailable text do not use clipboard capture without opt-in",
    arguments: [GrammarCheckError.empty, .unavailable])
  func clipboardOptIn(captureError: GrammarCheckError) async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.store.selectionBarClipboardFallbackIncludedApps = []
    fixture.access.captureError = captureError
    await Task.yield()
    await Task.yield()
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.failure?.message != nil }
    #expect(fixture.coordinator.review.failure?.recovery == .clipboard)
    #expect(fixture.access.clipboardCaptures == 0)
    #expect(await fixture.service.calls.isEmpty)
  }

  @Test("Configuration changes unregister the shortcut and invalidate requests")
  func settingsLifecycle() async throws {
    let fixture = GrammarFixture(mode: .hotkey, suspended: true)
    defer { fixture.close() }
    #expect(fixture.hotKey.shortcuts.last! == "cmd+ctrl+g")
    fixture.coordinator.checkManually()
    await eventually { await fixture.service.calls.count == 1 }
    fixture.store.grammar.shortcut = "cmd+ctrl+h"
    await eventually { fixture.hotKey.shortcuts.last! == "cmd+ctrl+h" }
    fixture.store.selectionBarEnabled = false
    await eventually { fixture.hotKey.shortcuts.last! == nil }
    #expect(!fixture.monitor.isRunning)
    await fixture.service.finish()
    #expect(fixture.coordinator.review.suggestions.isEmpty)
  }

  private func eventually(
    _ condition: () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    for _ in 0..<200 {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting for grammar state", sourceLocation: sourceLocation)
  }

  @Test(
    "Manual profiles are remembered without restarting monitoring; automatic checks stay neutral")
  func writingProfiles() async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { fixture.coordinator.review.result != nil }
    #expect(await fixture.service.profiles == [GrammarWritingProfile()])
    fixture.coordinator.openReview()
    let registrations = fixture.hotKey.shortcuts.count
    let origin = fixture.windows.last?.topLeft
    let profile = GrammarWritingProfile(refinement: .rewrite, tone: .formal)
    fixture.coordinator.changeProfile(profile)
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.store.grammar.manualProfile == profile)
    #expect(fixture.hotKey.shortcuts.count == registrations)
    #expect(fixture.windows.last?.topLeft == origin)
    #expect(await fixture.service.profiles.last == profile)
    #expect(fixture.coordinator.review.result == .rewrite("He is here. They are ready."))
    fixture.coordinator.handle(.dismiss)
    fixture.access.changeText("They is ready.")
    fixture.coordinator.handle(.input)
    await eventually { await fixture.service.profiles.count == 3 }
    #expect(await fixture.service.profiles.last == GrammarWritingProfile())
    #expect(fixture.store.grammar.manualProfile == profile)
  }

  @Test("Rapid profile changes retain the preview and only commit the latest request")
  func latestProfileWins() async throws {
    let fixture = GrammarFixture(mode: .hotkey, suspended: true)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { await fixture.service.calls.count == 1 }
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.phase == .ready }
    let preview = fixture.coordinator.review.outputText
    fixture.coordinator.changeProfile(.init(refinement: .rewrite, tone: .formal))
    await eventually { await fixture.service.calls.count == 2 }
    fixture.coordinator.changeProfile(.init(refinement: .grammar, tone: .casual))
    #expect(fixture.coordinator.review.phase == .checking)
    #expect(fixture.coordinator.review.outputText == preview)
    #expect(!fixture.coordinator.review.canApply)
    await fixture.service.finish()
    await eventually { await fixture.service.calls.count == 3 }
    await fixture.service.finish()
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.coordinator.review.profile == .init(refinement: .grammar, tone: .casual))
    #expect(fixture.coordinator.review.suggestions.count == 2)
    #expect(await fixture.service.maximumActive == 1)
  }

  @Test("Caret and scroll activity keep the panel; source edits require explicit recheck")
  func retainedReview() async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    let origin = fixture.windows.last?.topLeft
    let preview = fixture.coordinator.review.outputText
    fixture.access.current.selectionRange = NSRange(location: 4, length: 0)
    fixture.coordinator.handle(.changed)
    #expect(fixture.coordinator.review.phase == .ready)
    #expect(fixture.windows.last?.isVisible == true)
    fixture.coordinator.checkManually()
    #expect(await fixture.service.calls.count == 1)
    fixture.access.changeText("They is ready.")
    fixture.coordinator.handle(.changed)
    #expect(fixture.coordinator.review.phase == .stale)
    #expect(fixture.coordinator.review.outputText == preview)
    #expect(!fixture.coordinator.review.canApply)
    #expect(!fixture.coordinator.review.canUndo)
    #expect(fixture.windows.last?.topLeft == origin)
    #expect(await fixture.service.calls.count == 1)
    fixture.coordinator.recheck()
    await eventually { await fixture.service.calls.count == 2 }
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.access.restorations > 0)
    #expect(fixture.coordinator.review.originalText == "They is ready.")
    #expect(fixture.windows.last?.topLeft == origin)
  }

  @Test("Apply All and one-level Undo restore the exact original text and suggestions")
  func undoBatch() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    let before = fixture.access.current.text
    let suggestions = fixture.coordinator.review.suggestions
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase != .applying }
    #expect(fixture.coordinator.review.phase == .completed)
    #expect(fixture.coordinator.review.appliedCount == 2)
    #expect(fixture.coordinator.review.canUndo)
    #expect(fixture.access.current.text == "He is here. They are ready.")
    fixture.coordinator.undo()
    await eventually { fixture.coordinator.review.phase != .applying }
    #expect(fixture.access.current.text == before)
    #expect(fixture.coordinator.review.suggestions == suggestions)
    #expect(fixture.coordinator.review.appliedCount == 0)
    #expect(!fixture.coordinator.review.hasUndo)
    #expect(fixture.access.restorations == 4)
  }

  @Test("A finished review closes itself after Apply All or dismissing the last suggestion")
  func autoCloseWhenFinished() async throws {
    let applied = GrammarFixture(mode: .hotkey, autoCloseDelay: .milliseconds(30))
    defer { applied.close() }
    applied.coordinator.checkManually()
    await eventually { applied.coordinator.review.phase == .ready }
    applied.coordinator.applyAll()
    await eventually { applied.coordinator.review.phase == .completed }
    #expect(applied.windows.last?.isVisible == true)
    await eventually { applied.windows.last?.isVisible == false }

    let dismissed = GrammarFixture(mode: .hotkey, autoCloseDelay: .milliseconds(30))
    defer { dismissed.close() }
    dismissed.coordinator.checkManually()
    await eventually { dismissed.coordinator.review.phase == .ready }
    for suggestion in dismissed.coordinator.review.suggestions {
      dismissed.coordinator.dismissSuggestion(suggestion)
    }
    #expect(dismissed.coordinator.review.phase == .completed)
    await eventually { dismissed.windows.last?.isVisible == false }
  }

  @Test("Pending suggestions, Undo, and hovering keep the review open")
  func autoCloseDeferred() async throws {
    let fixture = GrammarFixture(mode: .hotkey, autoCloseDelay: .milliseconds(30))
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    fixture.coordinator.accept([fixture.coordinator.review.suggestions[0]])
    await eventually { fixture.coordinator.review.phase == .ready }
    try await Task.sleep(for: .milliseconds(120))
    #expect(fixture.windows.last?.isVisible == true)

    fixture.coordinator.accept(fixture.coordinator.review.suggestions)
    await eventually { fixture.coordinator.review.phase == .completed }
    fixture.coordinator.undo()
    await eventually { fixture.coordinator.review.phase == .ready }
    try await Task.sleep(for: .milliseconds(120))
    #expect(fixture.windows.last?.isVisible == true)

    fixture.coordinator.panelHoverChanged(true)
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase == .completed }
    try await Task.sleep(for: .milliseconds(120))
    #expect(fixture.windows.last?.isVisible == true)
    fixture.coordinator.panelHoverChanged(false)
    await eventually { fixture.windows.last?.isVisible == false }
  }

  @Test("Rewrite preview retains its original and supports Apply and Undo")
  func rewriteApplyUndo() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.store.grammar.manualProfile = .init(refinement: .rewrite, tone: .casual)
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    let before = fixture.access.current.text
    #expect(fixture.coordinator.review.previewOriginalText == before)
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase == .completed }
    #expect(fixture.coordinator.review.previewOriginalText == before)
    #expect(fixture.access.current.text == "He is here. They are ready.")
    fixture.coordinator.undo()
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.access.current.text == before)
  }

  @Test("Partial application stops without silently undoing successful edits")
  func partialApplication() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.access.failApplyAt = 2
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase == .failed }
    #expect(fixture.access.current.text == "He are here. They are ready.")
    #expect(fixture.access.applyAttempts == 2)
    #expect(fixture.coordinator.review.appliedCount == 1)
    #expect(!fixture.coordinator.review.canUndo)
    #expect(!fixture.coordinator.review.canApply)
    #expect(fixture.coordinator.review.failure?.recovery == .retry)
  }

  @Test("Focus failures and changed text prevent Apply and Undo")
  func guardedMutations() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    fixture.access.canRestoreFocus = false
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase == .failed }
    #expect(fixture.access.appliedOriginals.isEmpty)
    fixture.access.canRestoreFocus = true
    fixture.coordinator.recheck()
    await eventually { fixture.coordinator.review.phase == .ready }
    fixture.coordinator.applyAll()
    await eventually { fixture.coordinator.review.phase == .completed }
    let applied = fixture.access.appliedOriginals.count
    fixture.access.changeText("User edited the source")
    fixture.coordinator.undo()
    #expect(fixture.coordinator.review.phase == .stale)
    #expect(fixture.access.appliedOriginals.count == applied)
  }

  @Test("Moving to a different source closes the review")
  func differentSource() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    fixture.access.differentContext = true
    fixture.coordinator.handle(.focus)
    #expect(fixture.windows.last?.isVisible == false)
    #expect(fixture.coordinator.review.result == nil)
  }

  @Test("Provider failures preserve the preview and Retry uses the captured passage")
  func failureRecovery() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    let preview = fixture.coordinator.review.outputText
    let origin = fixture.windows.last?.topLeft
    let captures = fixture.access.preferredSelections.count
    await fixture.service.setFailure(.httpError(401, "fixture-secret"))
    fixture.coordinator.changeProfile(.init(refinement: .clarity, tone: .formal))
    await eventually { fixture.coordinator.review.phase == .failed }
    #expect(fixture.coordinator.review.outputText == preview)
    #expect(fixture.coordinator.review.failure?.recovery == .settings)
    #expect(fixture.coordinator.review.failure?.message.contains("fixture-secret") == false)
    await fixture.service.setFailure(nil)
    fixture.access.captureError = .composition
    fixture.coordinator.retry()
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.access.preferredSelections.count == captures)
    #expect(fixture.windows.last?.topLeft == origin)
    #expect(fixture.coordinator.review.profile.tone == .formal)
  }

  @Test("Suggestions are underlined in the source and follow dismissal, edits, and Escape")
  func underlineLifecycle() async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { fixture.underlines.markCount == 2 }
    let marks = try #require(fixture.underlines.layout?.marks)
    #expect(marks.map(\.id) == fixture.coordinator.review.suggestions.map(\.id))
    // "He are" starts at 0 and spans six characters.
    #expect(marks[0].rects == [CGRect(x: 0, y: 100, width: 60, height: 16)])

    fixture.coordinator.dismissSuggestion(fixture.coordinator.review.suggestions[0])
    #expect(fixture.underlines.markCount == 1)

    fixture.access.changeText("They is ready, he are.")
    fixture.coordinator.handle(.changed)
    #expect(fixture.underlines.layout == nil)

    fixture.coordinator.handle(.input)
    await eventually { fixture.underlines.markCount == 1 }
    fixture.coordinator.handle(.dismiss)
    #expect(fixture.underlines.layout == nil)
    fixture.coordinator.handle(.input)
    try await Task.sleep(for: .milliseconds(120))
    #expect(fixture.underlines.layout == nil)
  }

  @Test("Clicking an underline opens its suggestion without taking focus from the editor")
  func underlineClick() async throws {
    let fixture = GrammarFixture(mode: .automatic)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { fixture.underlines.markCount == 2 }
    let second = fixture.coordinator.review.suggestions[1]

    fixture.coordinator.handle(.click(CGPoint(x: 900, y: 300)))
    #expect(fixture.coordinator.review.highlighted == nil)

    // "They is" starts at 13: x 130–200, and the hit area reaches just below the text.
    fixture.coordinator.handle(.click(CGPoint(x: 150, y: 98)))
    #expect(fixture.coordinator.review.highlighted == second.id)
    #expect(fixture.underlines.highlighted == second.id)
    #expect(fixture.windows.last?.isVisible == true)
    #expect(fixture.windows.last?.isKey == false)
    #expect(fixture.windows.last?.caret == CGRect(x: 130, y: 100, width: 70, height: 16))
    #expect(await fixture.service.calls.count == 1)

    #expect(fixture.coordinator.review.currentSuggestion?.id == second.id)

    fixture.coordinator.accept([second])
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.underlines.markCount == 1)
    // The footer's Accept and Dismiss move on to the remaining suggestion.
    #expect(
      fixture.coordinator.review.currentSuggestion?.id
        == fixture.coordinator.review.suggestions.first?.id)
  }

  @Test("The review opens beside the caret, and without a known caret near the passage")
  func panelNearCaret() async throws {
    let fixture = GrammarFixture(mode: .hotkey)
    defer { fixture.close() }
    let caret = CGRect(x: 240, y: 500, width: 1, height: 17)
    fixture.access.current.caret = caret
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.windows.last?.caret == caret)

    fixture.coordinator.handle(.dismiss)
    fixture.access.current.caret = nil
    fixture.access.current.anchor = CGPoint(x: 80, y: 90)
    fixture.coordinator.checkManually()
    await eventually { fixture.coordinator.review.phase == .ready }
    #expect(fixture.windows.last?.caret == nil)
    #expect(fixture.windows.last?.topLeft == CGPoint(x: 80, y: 90))
  }

  @Test("Underlines stay off when disabled in settings")
  func underlinesDisabled() async throws {
    let fixture = GrammarFixture(mode: .automatic, showsUnderlines: false)
    defer { fixture.close() }
    fixture.coordinator.handle(.input)
    await eventually { fixture.coordinator.review.suggestions.count == 2 }
    #expect(fixture.underlines.layout == nil)
    fixture.coordinator.handle(.click(CGPoint(x: 10, y: 105)))
    #expect(fixture.coordinator.review.highlighted == nil)
  }
}

@MainActor
private final class GrammarFixture {
  let suite = "GrammarCoordinator.\(UUID())"
  let store: SelectionBarSettingsStore
  let access = GrammarTestAccess()
  let service: GrammarTestService
  let monitor = GrammarTestMonitor()
  let hotKey = GrammarTestHotKey()
  let windows = GrammarTestWindows()
  let underlines = GrammarTestUnderlines()
  let coordinator: GrammarCoordinator

  init(
    mode: GrammarTriggerMode, suspended: Bool = false, excludeAutomatic: Bool = false,
    showsUnderlines: Bool = true, autoCloseDelay: Duration = .seconds(60)
  ) {
    let keychain = InMemoryKeychain()
    _ = keychain.save(key: "openai_api_key", value: "fixture-key")
    store = SelectionBarSettingsStore(defaults: UserDefaults(suiteName: suite)!, keychain: keychain)
    store.selectionBarEnabled = true
    store.grammar.mode = mode
    store.grammar.providerID = "openai"
    store.grammar.shortcut = "cmd+ctrl+g"
    store.grammar.showsUnderlines = showsUnderlines
    if excludeAutomatic {
      store.grammar.excludedApps = [IgnoredApp(id: "grammar.test", name: "Test")]
    }
    service = GrammarTestService(suspended: suspended)
    coordinator = GrammarCoordinator(
      settingsStore: store, access: access, service: service, monitor: monitor, hotKey: hotKey,
      windowFactory: { [windows] _ in windows.makeWindow() }, underlines: underlines,
      sleep: { _ in try await Task.sleep(for: .milliseconds(20)) }, autoCloseDelay: autoCloseDelay)
  }

  func close() {
    coordinator.stop()
    store.flushPendingWrites()
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
}

@MainActor
private final class GrammarTestAccess: GrammarTextAccessing {
  var current = GrammarTextSnapshot(
    targetID: UUID(), processID: 42, bundleID: "grammar.test",
    fullText: "He are here. They is ready.", checkedRange: NSRange(location: 0, length: 26),
    selectionRange: NSRange(location: 0, length: 0), text: "He are here. They is ready.",
    anchor: .zero, canApply: true)
  var preferredSelections: [Bool] = []
  var appliedOriginals: [String] = []
  var captureError: GrammarCheckError?
  var clipboardCaptures = 0
  var differentContext = false
  var canRestoreFocus = true
  var restorations = 0
  var failApplyAt: Int?
  var applyAttempts = 0

  func changeText(_ text: String) {
    current.text = text
    current.fullText = text
    current.checkedRange.length = text.utf16.count
  }

  func capture(preferSelection: Bool) throws -> GrammarTextSnapshot {
    preferredSelections.append(preferSelection)
    if let captureError { throw captureError }
    return current
  }

  func captureClipboardSelection() async throws -> GrammarTextSnapshot {
    clipboardCaptures += 1
    current.canApply = false
    return current
  }

  func isCurrent(_ snapshot: GrammarTextSnapshot, checkSelection: Bool) -> Bool {
    current.hasSameContent(as: snapshot)
  }

  func sourceStatus(_ snapshot: GrammarTextSnapshot, allowPanelFocus: Bool) -> GrammarSourceStatus {
    if differentContext || current.targetID != snapshot.targetID { return .differentContext }
    return GrammarText.identical(current.fullText, snapshot.fullText) ? .current : .changed
  }

  func prepareSource(_ snapshot: GrammarTextSnapshot, requireUnchanged: Bool) async throws {
    guard canRestoreFocus, sourceStatus(snapshot, allowPanelFocus: true) != .differentContext,
      !requireUnchanged || sourceStatus(snapshot, allowPanelFocus: true) == .current
    else {
      throw GrammarCheckError.changed
    }
    restorations += 1
  }

  /// Lays text out on one line at 10pt per UTF-16 unit, 16pt tall, starting at (0, 100).
  func underlineLayout(for suggestions: [GrammarSuggestion], in snapshot: GrammarTextSnapshot)
    -> GrammarUnderlineLayout?
  {
    GrammarUnderlineLayout(
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 400),
      marks: suggestions.map { suggestion in
        let location = snapshot.checkedRange.location + suggestion.range.location
        return .init(
          id: suggestion.id, category: suggestion.category,
          rects: [
            CGRect(
              x: CGFloat(location * 10), y: 100, width: CGFloat(suggestion.range.length * 10),
              height: 16)
          ])
      })
  }

  func apply(_ suggestion: GrammarSuggestion, to snapshot: GrammarTextSnapshot) async throws
    -> GrammarTextSnapshot
  {
    try await prepareSource(snapshot, requireUnchanged: true)
    applyAttempts += 1
    if applyAttempts == failApplyAt { throw GrammarCheckError.applyFailed }
    guard isCurrent(snapshot, checkSelection: true) else { throw GrammarCheckError.changed }
    appliedOriginals.append(suggestion.original)
    changeText(GrammarText.replacing(current.text, with: [suggestion]))
    return current
  }
}

private actor GrammarTestService: GrammarChecking {
  let suspended: Bool
  var calls: [String] = []
  var profiles: [GrammarWritingProfile] = []
  var failure: SelectionBarError?

  func setFailure(_ error: SelectionBarError?) { failure = error }
  var continuations: [CheckedContinuation<Void, Never>] = []
  var active = 0
  var maximumActive = 0

  init(suspended: Bool) { self.suspended = suspended }

  func check(
    text: String, profile: GrammarWritingProfile, settings: GrammarSettings, language: String,
    providers: SelectionBarProviderSettingsSnapshot
  ) async throws -> GrammarCheckResult {
    calls.append(text)
    profiles.append(profile)
    active += 1
    maximumActive = max(active, maximumActive)
    defer { active -= 1 }
    if suspended { await withCheckedContinuation { continuations.append($0) } }
    if let failure { throw failure }
    let suggestions: [GrammarSuggestion] = [("He are", "He is"), ("They is", "They are")].compactMap
    { original, replacement in
      let range = (text as NSString).range(of: original)
      guard range.location != NSNotFound else { return nil }
      return GrammarSuggestion(
        id: UUID(), original: original, replacement: replacement,
        category: .correctness, explanation: "Agreement", range: range)
    }
    if profile.refinement == .rewrite {
      return .rewrite(GrammarText.replacing(text, with: suggestions))
    }
    return .suggestions(suggestions)
  }

  func finish() { if !continuations.isEmpty { continuations.removeFirst().resume() } }
}

@MainActor
private final class GrammarTestMonitor: GrammarMonitoring {
  var isRunning = false
  func start(shortcut: String, onChange: @escaping (GrammarMonitorEvent) -> Void) {
    isRunning = true
  }
  func stop() { isRunning = false }
}

@MainActor
private final class GrammarTestHotKey: GrammarHotKeyRegistering {
  var shortcuts: [String?] = []
  func configure(shortcut: String?, action: @escaping () -> Void) -> String? {
    shortcuts.append(shortcut)
    return nil
  }
}

@MainActor
private final class GrammarTestWindows {
  private(set) var last: GrammarTestWindow?

  func makeWindow() -> GrammarTestWindow {
    let window = GrammarTestWindow()
    last = window
    return window
  }
}

@MainActor
private final class GrammarTestWindow: GrammarWindowPresenting {
  var topLeft: NSPoint? = .zero
  var isKey = false
  var onDismiss: (() -> Void)?
  var isVisible = false
  func showNear(point: NSPoint) {
    topLeft = point
    isVisible = true
  }
  private(set) var caret: CGRect?
  func place(near caret: CGRect) {
    self.caret = caret
    topLeft = NSPoint(x: caret.minX, y: caret.minY)
  }
  func update(content: AnyView, interactive: Bool) {}
  func resizeToFit() {}
  func focus() { isKey = true }
  func dismiss() {
    isVisible = false
    isKey = false
  }
}

@MainActor
private final class GrammarTestUnderlines: GrammarUnderlinePresenting {
  private(set) var layout: GrammarUnderlineLayout?
  private(set) var highlighted: UUID?

  var markCount: Int { layout?.marks.count ?? 0 }

  func show(_ layout: GrammarUnderlineLayout, highlighted: UUID?) {
    self.layout = layout
    self.highlighted = highlighted
  }
  func highlight(_ id: UUID?) { highlighted = id }
  func hide() { layout = nil }
}
