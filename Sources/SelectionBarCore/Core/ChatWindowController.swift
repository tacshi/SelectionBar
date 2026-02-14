import AppKit
import SwiftUI

/// A panel that can become key (so the text field can accept input) but doesn't activate the app.
private class ChatPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  /// Handle Escape by dismissing the panel.
  override func cancelOperation(_ sender: Any?) {
    orderOut(sender)
  }
}

/// Window controller for the floating chat panel.
@MainActor
final class ChatWindowController: NSWindowController {
  var onDismiss: (() -> Void)?

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
    window?.orderOut(nil)
  }
}
