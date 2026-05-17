import AppKit
import Foundation
import SwiftUI
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarCoordinator Tests")
@MainActor
struct SelectionBarCoordinatorTests {
  @Test("selection popup is not blocked by run command visibility resolution")
  func selectionPopupIsNotBlockedByRunCommandVisibilityResolution() async throws {
    let store = makeStore(keychain: InMemoryKeychain())
    let windowPresenter = FakeSelectionBarWindowPresenter()
    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in windowPresenter },
      runCommandVisibilityResolver: { _ in
        try? await Task.sleep(for: .milliseconds(200))
        return false
      }
    )

    let start = CFAbsoluteTimeGetCurrent()
    coordinator.handleTextSelectedForTesting(text: "git status", at: NSPoint(x: 80, y: 120))
    let elapsed = CFAbsoluteTimeGetCurrent() - start

    #expect(elapsed < 0.05)
    #expect(windowPresenter.showNearCalls == 1)
    #expect(windowPresenter.updateCalls == 0)

    try await Task.sleep(for: .milliseconds(260))

    #expect(windowPresenter.updateCalls == 0)
  }

  @Test("run command visibility update rebuilds an existing popup")
  func runCommandVisibilityUpdateRebuildsExistingPopup() async throws {
    let store = makeStore(keychain: InMemoryKeychain())
    let windowPresenter = FakeSelectionBarWindowPresenter()
    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in windowPresenter },
      runCommandVisibilityResolver: { _ in true }
    )

    coordinator.handleTextSelectedForTesting(
      text: "/usr/bin/git status",
      at: NSPoint(x: 90, y: 130)
    )

    #expect(windowPresenter.showNearCalls == 1)
    #expect(windowPresenter.updateCalls == 0)

    try await Task.sleep(for: .milliseconds(120))

    #expect(windowPresenter.updateCalls == 1)
    #expect(windowPresenter.showAtOriginCalls == 1)
  }

  @Test("stale run command visibility tasks do not affect a newer selection")
  func staleRunCommandVisibilityTasksDoNotAffectNewerSelection() async throws {
    let store = makeStore(keychain: InMemoryKeychain())
    let windowPresenter = FakeSelectionBarWindowPresenter()
    var resolvedTexts: [String] = []

    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in windowPresenter },
      runCommandVisibilityResolver: { text in
        resolvedTexts.append(text)
        return text.contains("/usr/bin/git")
      }
    )

    coordinator.handleTextSelectedForTesting(
      text: "/usr/bin/git status",
      at: NSPoint(x: 100, y: 140)
    )
    coordinator.handleTextSelectedForTesting(
      text: "plain text",
      at: NSPoint(x: 110, y: 150)
    )

    try await Task.sleep(for: .milliseconds(200))

    #expect(windowPresenter.showNearCalls == 2)
    #expect(windowPresenter.dismissCalls == 1)
    #expect(windowPresenter.updateCalls == 0)
    #expect(resolvedTexts == ["plain text"])
  }

  @Test("selection popup uses profile actions for selected app bundle")
  func selectionPopupUsesProfileActionsForSelectedAppBundle() {
    let store = makeStore(keychain: InMemoryKeychain())
    let globalAction = makeJavaScriptAction(name: "Global", isEnabled: true)
    let profileAction = makeJavaScriptAction(name: "Profile", isEnabled: false)
    store.customActions = [globalAction, profileAction]
    store.actionProfiles = [
      SelectionBarActionProfile(
        app: IgnoredApp(id: "com.example.Editor", name: "Editor"),
        isEnabled: true,
        actionIDs: [profileAction.id]
      )
    ]

    var observedActionIDs: [[UUID]] = []
    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in FakeSelectionBarWindowPresenter() },
      runCommandVisibilityResolver: { _ in false },
      barActionsObserver: { actions in
        observedActionIDs.append(actions.map(\.id))
      }
    )

    coordinator.handleTextSelectedForTesting(
      text: "selected text",
      at: NSPoint(x: 80, y: 120),
      frontmostBundleID: "com.example.Editor"
    )

    #expect(observedActionIDs.first == [profileAction.id])
  }

  @Test("selection popup uses global actions for unknown app bundle")
  func selectionPopupUsesGlobalActionsForUnknownAppBundle() {
    let store = makeStore(keychain: InMemoryKeychain())
    let globalAction = makeJavaScriptAction(name: "Global", isEnabled: true)
    let profileAction = makeJavaScriptAction(name: "Profile", isEnabled: false)
    store.customActions = [globalAction, profileAction]
    store.actionProfiles = [
      SelectionBarActionProfile(
        app: IgnoredApp(id: "com.example.Editor", name: "Editor"),
        isEnabled: true,
        actionIDs: [profileAction.id]
      )
    ]

    var observedActionIDs: [[UUID]] = []
    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in FakeSelectionBarWindowPresenter() },
      runCommandVisibilityResolver: { _ in false },
      barActionsObserver: { actions in
        observedActionIDs.append(actions.map(\.id))
      }
    )

    coordinator.handleTextSelectedForTesting(
      text: "selected text",
      at: NSPoint(x: 80, y: 120),
      frontmostBundleID: "com.example.Other"
    )

    #expect(observedActionIDs.first == [globalAction.id])
  }

  @Test("selection popup rebuild keeps captured selected app profile")
  func selectionPopupRebuildKeepsCapturedSelectedAppProfile() async throws {
    let store = makeStore(keychain: InMemoryKeychain())
    let globalAction = makeJavaScriptAction(name: "Global", isEnabled: true)
    let profileAction = makeJavaScriptAction(name: "Profile", isEnabled: false)
    let windowPresenter = FakeSelectionBarWindowPresenter()
    store.customActions = [globalAction, profileAction]
    store.actionProfiles = [
      SelectionBarActionProfile(
        app: IgnoredApp(id: "com.example.Editor", name: "Editor"),
        isEnabled: true,
        actionIDs: [profileAction.id]
      )
    ]

    var observedActionIDs: [[UUID]] = []
    let coordinator = SelectionBarCoordinator(
      settingsStore: store,
      monitor: SelectionMonitor(),
      actionHandler: SelectionBarActionHandler(),
      windowControllerFactory: { _ in windowPresenter },
      runCommandVisibilityResolver: { _ in true },
      barActionsObserver: { actions in
        observedActionIDs.append(actions.map(\.id))
      }
    )

    coordinator.handleTextSelectedForTesting(
      text: "/usr/bin/git status",
      at: NSPoint(x: 80, y: 120),
      frontmostBundleID: "com.example.Editor"
    )

    try await Task.sleep(for: .milliseconds(120))

    #expect(windowPresenter.updateCalls == 1)
    #expect(observedActionIDs.count >= 2)
    #expect(observedActionIDs.allSatisfy { $0 == [profileAction.id] })
  }
}

private func makeJavaScriptAction(name: String, isEnabled: Bool) -> CustomActionConfig {
  CustomActionConfig(
    id: UUID(),
    name: name,
    prompt: "",
    modelProvider: "",
    modelId: "",
    kind: .javascript,
    script: "function transform(input) { return input; }",
    isEnabled: isEnabled
  )
}

@MainActor
private final class FakeSelectionBarWindowPresenter: SelectionBarWindowPresenting {
  private(set) var showNearCalls = 0
  private(set) var showAtOriginCalls = 0
  private(set) var updateCalls = 0
  private(set) var dismissCalls = 0
  var currentOrigin: NSPoint?
  var isVisible = false

  func showNear(point: NSPoint) {
    showNearCalls += 1
    currentOrigin = point
    isVisible = true
  }

  func show(atOrigin origin: NSPoint) {
    showAtOriginCalls += 1
    currentOrigin = origin
    isVisible = true
  }

  func update(anyContentView _: AnyView) {
    updateCalls += 1
  }

  func dismiss() {
    dismissCalls += 1
    isVisible = false
  }
}
