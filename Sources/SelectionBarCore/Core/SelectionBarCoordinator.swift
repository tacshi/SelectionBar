import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "SelectionBarCoordinator")

/// Coordinates the selection bar lifecycle: monitor -> window -> action handler.
@MainActor
public final class SelectionBarCoordinator {
  private let settingsStore: SelectionBarSettingsStore
  private let monitor = SelectionMonitor()
  private let actionHandler = SelectionBarActionHandler()
  private var windowController: SelectionBarWindowController?
  private var actionTask: Task<Void, Never>?
  private var autoDismissTask: Task<Void, Never>?

  private var chatWindowController: ChatWindowController?
  private var chatSession: ChatSession?

  private var selectedText: String?
  private var processedText: String?
  private var processingActionId: UUID?
  private var errorActionId: UUID?
  private var isTranslating = false
  private var isTranslateError = false
  private var isSpeaking = false

  public init(settingsStore: SelectionBarSettingsStore) {
    self.settingsStore = settingsStore

    monitor.onTextSelected = { [weak self] text, location in
      self?.handleTextSelected(text: text, at: location)
    }
    monitor.onDismissRequested = { [weak self] in
      self?.dismiss()
    }

    updateIgnoredApps()
    updateActivationRequirement()

    if settingsStore.selectionBarEnabled {
      logger.info("Selection bar enabled at launch, starting monitor")
      _ = monitor.checkAccessibilityPermission(promptIfNeeded: true)
      monitor.start()
    } else {
      logger.info("Selection bar disabled at launch")
    }
  }

  /// Called when the enabled setting changes.
  public func updateEnabled() {
    updateIgnoredApps()
    updateActivationRequirement()

    if settingsStore.selectionBarEnabled {
      logger.info("Selection bar toggled ON, starting monitor")
      _ = monitor.checkAccessibilityPermission(promptIfNeeded: true)
      monitor.start()
    } else {
      logger.info("Selection bar toggled OFF, stopping monitor")
      monitor.stop()
      dismiss()
    }
  }

  /// Sync ignored apps from settings to monitor.
  public func updateIgnoredApps() {
    monitor.ignoredBundleIDs = Set(settingsStore.selectionBarIgnoredApps.map(\.id))
  }

  /// Sync activation gating settings to monitor.
  public func updateActivationRequirement() {
    monitor.requireActivationModifier = settingsStore.selectionBarDoNotDisturbEnabled
    monitor.requiredActivationModifier = settingsStore.selectionBarActivationModifier
  }

  private func handleTextSelected(text: String, at location: NSPoint) {
    let enabledActions = settingsStore.customActions.filter(\.isEnabled)
    logger.info(
      "Showing selection bar near (\(location.x, privacy: .public), \(location.y, privacy: .public)) with \(enabledActions.count, privacy: .public) custom actions"
    )

    dismiss()

    selectedText = text
    processedText = nil
    processingActionId = nil
    errorActionId = nil
    isTranslating = false
    isTranslateError = false
    isSpeaking = false
    actionHandler.stopSpeaking()

    showBar(near: location)
    startAutoDismissTimer()
  }

  private func showBar(near location: NSPoint) {
    let controller = SelectionBarWindowController(contentView: makeBarView())
    controller.showNear(point: location)
    windowController = controller
  }

  private func makeBarView() -> SelectionBarView {
    let showOpenURL =
      if let selectedText {
        actionHandler.urlToOpen(text: selectedText) != nil
      } else {
        false
      }

    let showLookup: Bool
    if settingsStore.selectionBarLookupEnabled {
      switch settingsStore.selectionBarLookupProvider {
      case .systemDictionary, .eudic:
        showLookup = true
      case .customApp:
        showLookup = !settingsStore.selectionBarLookupCustomScheme.trimmingCharacters(
          in: .whitespacesAndNewlines
        ).isEmpty
      }
    } else {
      showLookup = false
    }

    let showTranslate =
      settingsStore.selectionBarTranslationEnabled
      && !settingsStore.availableSelectionBarTranslationProviders().isEmpty
    let showSpeak = settingsStore.selectionBarSpeakEnabled
    let showChat =
      settingsStore.selectionBarChatEnabled
      && !settingsStore.availableChatProviders().isEmpty
    let showCut = monitor.isFocusedElementEditable()
    let enabledActions = settingsStore.customActions.filter(\.isEnabled)
    let isBusy = processingActionId != nil || isTranslating

    return SelectionBarView(
      actions: enabledActions,
      processingActionId: processingActionId,
      errorActionId: errorActionId,
      showCut: showCut,
      showSearch: true,
      showOpenURL: showOpenURL,
      showLookup: showLookup,
      showTranslate: showTranslate,
      isTranslating: isTranslating,
      isTranslateError: isTranslateError,
      showSpeak: showSpeak,
      isSpeaking: isSpeaking,
      showChat: showChat,
      isBusy: isBusy,
      onSearchSelected: { [weak self] in
        self?.handleSearchSelected()
      },
      onOpenURLSelected: { [weak self] in
        self?.handleOpenURLSelected()
      },
      onCopySelected: { [weak self] in
        self?.handleCopySelected()
      },
      onCutSelected: { [weak self] in
        self?.handleCutSelected()
      },
      onLookupSelected: { [weak self] in
        self?.handleLookupSelected()
      },
      onTranslateSelected: { [weak self] in
        self?.handleTranslateSelected()
      },
      onSpeakSelected: { [weak self] in
        self?.handleSpeakSelected()
      },
      onChatSelected: { [weak self] in
        self?.handleChatSelected()
      },
      onActionSelected: { [weak self] action in
        self?.handleActionSelected(action)
      }
    )
  }

  private func rebuildBarIfVisible() {
    guard let controller = windowController,
      let window = controller.window,
      window.isVisible
    else { return }
    let origin = window.frame.origin
    controller.update(contentView: makeBarView())
    controller.show(atOrigin: origin)
  }

  private func handleTranslateSelected() {
    guard let selectedText else { return }
    guard settingsStore.selectionBarTranslationEnabled else { return }

    settingsStore.ensureValidSelectionBarTranslationProvider()
    settingsStore.ensureValidSelectionBarTranslationTargetLanguage()
    let selectedProviderId = settingsStore.selectionBarTranslationProviderId

    actionTask?.cancel()
    autoDismissTask?.cancel()

    processingActionId = nil
    errorActionId = nil
    isTranslating = true
    isTranslateError = false
    rebuildBarIfVisible()

    actionTask = Task { [weak self] in
      guard let self else { return }
      if SelectionBarTranslationAppProvider(rawValue: selectedProviderId) != nil {
        let didOpen = await self.actionHandler.translateWithApp(
          text: selectedText,
          providerId: selectedProviderId
        )
        guard !Task.isCancelled else { return }

        self.isTranslating = false
        self.actionTask = nil

        if didOpen {
          self.dismiss()
        } else {
          logger.error("Translate action failed to open translation app")
          self.showTranslateError()
        }
        return
      }

      do {
        let result = try await self.actionHandler.translate(
          text: selectedText,
          providerId: selectedProviderId,
          targetLanguageCode: self.settingsStore.selectionBarTranslationTargetLanguage,
          settings: self.settingsStore
        )
        guard !Task.isCancelled else { return }
        self.showProcessedResult(result)
      } catch {
        guard !Task.isCancelled else { return }
        logger.error("Translate action failed: \(error.localizedDescription, privacy: .public)")
        self.showTranslateError()
      }
    }
  }

  private func handleSpeakSelected() {
    if isSpeaking {
      actionHandler.stopSpeaking()
      isSpeaking = false
      rebuildBarIfVisible()
      return
    }

    guard let selectedText else { return }

    settingsStore.ensureValidSelectionBarSpeakProvider()

    autoDismissTask?.cancel()
    isSpeaking = true
    rebuildBarIfVisible()

    let providerId = settingsStore.selectionBarSpeakProviderId

    if SelectionBarSpeakAPIProvider(rawValue: providerId) == .elevenLabs {
      let voiceId = settingsStore.elevenLabsVoiceId
      let modelId = settingsStore.elevenLabsModelId
      actionHandler.speakWithElevenLabs(
        text: selectedText, voiceId: voiceId, modelId: modelId
      ) { [weak self] in
        guard let self else { return }
        self.isSpeaking = false
        self.rebuildBarIfVisible()
      }
    } else {
      let voiceId = settingsStore.selectionBarSpeakVoiceIdentifier
      actionHandler.speak(
        text: selectedText, voiceIdentifier: voiceId, providerId: providerId
      ) { [weak self] in
        guard let self else { return }
        self.isSpeaking = false
        self.rebuildBarIfVisible()
      }
    }
  }

  private func handleActionSelected(_ action: CustomActionConfig) {
    guard let selectedText else { return }

    logger.info("Custom action selected: \(action.localizedName, privacy: .public)")

    actionTask?.cancel()
    autoDismissTask?.cancel()

    processingActionId = action.id
    errorActionId = nil
    isTranslating = false
    isTranslateError = false
    rebuildBarIfVisible()

    actionTask = Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await self.actionHandler.process(
          text: selectedText,
          action: action,
          settings: self.settingsStore
        )
        guard !Task.isCancelled else { return }
        if action.kind == .javascript && action.outputMode == .inplace {
          if self.monitor.isFocusedElementEditable() {
            self.processingActionId = nil
            self.errorActionId = nil
            self.isTranslating = false
            self.isTranslateError = false
            self.actionTask = nil
            await self.actionHandler.replaceSelectedText(with: result)
            guard !Task.isCancelled else { return }
            self.dismiss()
          } else {
            self.showProcessedResult(result)
          }
        } else {
          self.showProcessedResult(result)
        }
      } catch {
        guard !Task.isCancelled else { return }
        logger.error("Custom action failed: \(error.localizedDescription, privacy: .public)")
        self.showActionError(for: action.id)
      }
    }
  }

  private func handleChatSelected() {
    guard let selectedText else { return }

    autoDismissTask?.cancel()
    autoDismissTask = nil

    windowController?.dismiss()
    windowController = nil

    settingsStore.ensureValidChatProvider()

    let client = SelectionBarOpenAIClient()
    let snapshot = SelectionBarProviderSettingsSnapshot(
      openAIModel: settingsStore.openAIModel,
      openAITranslationModel: "",
      openRouterModel: settingsStore.openRouterModel,
      openRouterTranslationModel: "",
      customLLMProviders: settingsStore.customLLMProviders
    )

    let providerId = settingsStore.selectionBarChatProviderId
    let modelId = settingsStore.selectionBarChatModelId

    guard
      let context = try? client.resolveProviderContext(
        providerId: providerId,
        explicitModelId: modelId,
        preferTranslationModel: false,
        settingsSnapshot: snapshot
      )
    else {
      logger.error("Chat: failed to resolve provider context for \(providerId)")
      return
    }

    let canApply = monitor.isFocusedElementEditable()
    let frontmostApp = NSWorkspace.shared.frontmostApplication
    let frontmostBundleID = frontmostApp?.bundleIdentifier
    let frontmostPID = frontmostApp?.processIdentifier
    logger.info("Chat: frontmost app bundle ID: \(frontmostBundleID ?? "nil", privacy: .public)")

    Task {
      let sourceURL = await SourceContextService.resolveSource(
        bundleID: frontmostBundleID, pid: frontmostPID)
      logger.info("Chat: source: \(sourceURL ?? "nil", privacy: .public)")

      let session = ChatSession(
        selectedText: selectedText, sourceURL: sourceURL, client: client, context: context)
      self.chatSession = session

      let chatView = ChatPanelView(
        session: session,
        selectedText: selectedText,
        sourceURL: sourceURL,
        canApply: canApply,
        onCopy: { [weak self] text in
          self?.actionHandler.copyToClipboard(text)
        },
        onApply: { [weak self] text in
          self?.actionTask?.cancel()
          self?.actionTask = Task { [weak self] in
            // Dismiss chat first so the browser regains keyboard focus,
            // then the simulated Cmd+V paste goes to the browser.
            self?.dismissChat()
            try? await Task.sleep(for: .milliseconds(100))
            await self?.actionHandler.replaceSelectedText(with: text)
          }
        },
        onTogglePin: { [weak self] pinned in
          self?.chatWindowController?.setPin(pinned)
        },
        onDismiss: { [weak self] in
          self?.dismissChat()
        }
      )

      let controller = ChatWindowController(contentView: chatView)
      controller.onDismiss = { [weak self] in
        self?.dismissChat()
      }
      controller.showCentered()
      self.chatWindowController = controller
    }
  }

  private func dismissChat() {
    chatSession?.cancelStreaming()
    chatSession = nil
    chatWindowController?.dismiss()
    chatWindowController = nil
  }

  private func handleLookupSelected() {
    guard let selectedText else { return }
    let didOpen = actionHandler.lookUp(text: selectedText, settings: settingsStore)
    if didOpen {
      dismiss()
    } else {
      logger.error("Look up action failed to open dictionary app")
    }
  }

  private func handleSearchSelected() {
    guard let selectedText else { return }
    let didOpen = actionHandler.searchWeb(text: selectedText, settings: settingsStore)
    if didOpen {
      dismiss()
    } else {
      logger.error("Search action failed to open browser URL")
    }
  }

  private func handleOpenURLSelected() {
    guard let selectedText else { return }
    let didOpen = actionHandler.openURL(text: selectedText)
    if didOpen {
      dismiss()
    } else {
      logger.error("Open URL action failed")
    }
  }

  private func handleCopySelected() {
    guard let selectedText else { return }
    actionHandler.copyToClipboard(selectedText)
    dismiss()
  }

  private func handleCutSelected() {
    guard selectedText != nil else { return }
    let didCut = actionHandler.cutSelection()
    if didCut {
      dismiss()
    } else {
      logger.error("Cut action failed")
    }
  }

  private func showTranslateError() {
    processingActionId = nil
    errorActionId = nil
    isTranslating = false
    isTranslateError = true
    actionTask = nil
    rebuildBarIfVisible()

    autoDismissTask?.cancel()
    autoDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  private func showActionError(for actionId: UUID) {
    processingActionId = nil
    errorActionId = actionId
    isTranslating = false
    isTranslateError = false
    actionTask = nil
    rebuildBarIfVisible()

    autoDismissTask?.cancel()
    autoDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  private func showProcessedResult(_ result: String) {
    let canApply = monitor.isFocusedElementEditable()
    processedText = result
    processingActionId = nil
    errorActionId = nil
    isTranslating = false
    isTranslateError = false
    actionTask = nil

    let origin = windowController?.currentOrigin
    let view = SelectionResultView(
      result: result,
      canApply: canApply,
      onDiscard: { [weak self] in
        self?.dismiss()
      },
      onCopy: { [weak self] text in
        self?.copyProcessedResult(text)
      },
      onApply: { [weak self] in
        self?.applyProcessedResult()
      }
    )

    if let controller = windowController {
      controller.update(contentView: view)
      if let origin {
        controller.show(atOrigin: origin)
      } else {
        controller.showNear(point: NSEvent.mouseLocation)
      }
      return
    }

    let controller = SelectionBarWindowController(contentView: view)
    if let origin {
      controller.show(atOrigin: origin)
    } else {
      controller.showNear(point: NSEvent.mouseLocation)
    }
    windowController = controller
  }

  private func copyProcessedResult(_ text: String? = nil) {
    let content = text ?? processedText
    guard let content else { return }
    actionHandler.copyToClipboard(content)
    dismiss()
  }

  private func applyProcessedResult() {
    guard let processedText else { return }
    actionTask?.cancel()
    actionTask = Task { [weak self] in
      await self?.actionHandler.replaceSelectedText(with: processedText)
      self?.dismiss()
    }
  }

  private func startAutoDismissTimer() {
    autoDismissTask?.cancel()
    autoDismissTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(10))
      guard !Task.isCancelled else { return }
      self?.dismiss()
    }
  }

  private func dismiss() {
    actionTask?.cancel()
    actionTask = nil
    autoDismissTask?.cancel()
    autoDismissTask = nil
    actionHandler.stopSpeaking()
    windowController?.dismiss()
    windowController = nil
    selectedText = nil
    processedText = nil
    processingActionId = nil
    errorActionId = nil
    isTranslating = false
    isTranslateError = false
    isSpeaking = false
  }
}
