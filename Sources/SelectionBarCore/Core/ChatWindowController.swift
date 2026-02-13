import AppKit
import SwiftUI

/// A panel that can become key (so the text field can accept input) but doesn't activate the app.
private class ChatPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  var onEscapePressed: (() -> Void)?

  override func cancelOperation(_ sender: Any?) {
    onEscapePressed?()
  }
}

/// Window controller for the floating chat panel.
@MainActor
final class ChatWindowController: NSWindowController {
  var onDismiss: (() -> Void)?
  private var globalEscMonitor: Any?
  private var localEscMonitor: Any?

  init(contentView: some View) {
    let hostingView = NSHostingView(rootView: AnyView(contentView))
    hostingView.sizingOptions = [.intrinsicContentSize]

    let window = ChatPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.level = .floating
    window.ignoresMouseEvents = false
    window.isMovableByWindowBackground = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    window.contentView = hostingView

    super.init(window: window)

    window.onEscapePressed = { [weak self] in
      self?.onDismiss?()
    }

    // Global monitor: catches Escape when the chat window is not focused
    globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {  // Escape
        Task { @MainActor in self?.onDismiss?() }
      }
    }

    // Local monitor: catches Escape when the app is active but a different window is key
    localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        Task { @MainActor in self?.onDismiss?() }
        return nil  // consume the event
      }
      return event
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func showCentered() {
    guard let window = window else { return }

    let contentSize = NSSize(width: 420, height: 480)
    window.setContentSize(contentSize)

    let mouseLocation = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main

    if let screen {
      let visibleFrame = screen.visibleFrame
      let x = visibleFrame.midX - contentSize.width / 2
      let y = visibleFrame.midY - contentSize.height / 2
      window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    window.makeKeyAndOrderFront(nil)
  }

  func setPin(_ pinned: Bool) {
    window?.level = pinned ? .floating : .normal
  }

  func dismiss() {
    if let globalEscMonitor {
      NSEvent.removeMonitor(globalEscMonitor)
      self.globalEscMonitor = nil
    }
    if let localEscMonitor {
      NSEvent.removeMonitor(localEscMonitor)
      self.localEscMonitor = nil
    }
    window?.orderOut(nil)
  }
}
