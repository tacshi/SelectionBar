import AppKit
import SwiftUI

@MainActor
protocol GrammarWindowPresenting: AnyObject {
  var topLeft: NSPoint? { get }
  var isKey: Bool { get }
  var isVisible: Bool { get }
  var onDismiss: (() -> Void)? { get set }
  func showNear(point: NSPoint)
  /// Keeps the panel beside the caret's line, below it when it fits and above otherwise.
  func place(near caret: CGRect)
  func update(content: AnyView, interactive: Bool)
  func resizeToFit()
  func focus()
  func dismiss()
}

private final class GrammarPanel: NSPanel {
  var allowsKeyboardFocus = false
  var dismissAction: (() -> Void)?
  var constrainAfterDrag: (() -> Void)?
  override var canBecomeKey: Bool { allowsKeyboardFocus }
  override var canBecomeMain: Bool { false }
  override func cancelOperation(_ sender: Any?) { dismissAction?() }
}

@MainActor
final class GrammarWindowController: NSWindowController, GrammarWindowPresenting {
  static var ownsKeyboardFocus: Bool { NSApp.keyWindow is GrammarPanel }

  /// Hands keyboard input back to the app underneath. A non-activating panel keeps receiving
  /// keystrokes until it leaves the screen; calling `resignKey()` only updates AppKit's own state.
  static func releaseKeyboardFocus() {
    guard let panel = NSApp.keyWindow as? GrammarPanel else { return }
    panel.orderOut(nil)
    panel.orderFrontRegardless()
  }
  private let hostingView: NSHostingView<AnyView>
  private var caret: CGRect?
  private var placedAbove = false
  var onDismiss: (() -> Void)? {
    didSet { (window as? GrammarPanel)?.dismissAction = onDismiss }
  }

  init(content: AnyView) {
    hostingView = NSHostingView(rootView: content)
    hostingView.sizingOptions = [.intrinsicContentSize]
    let panel = GrammarPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.identifier = NSUserInterfaceItemIdentifier("SelectionBar.Grammar")
    panel.title = String(localized: "Grammar", bundle: .localizedModule)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = hostingView
    super.init(window: panel)
    panel.constrainAfterDrag = { [weak self] in
      guard let self, let anchor = self.topLeft else { return }
      // A panel the user moved stays where they put it.
      self.caret = nil
      self.position(topLeft: anchor, screen: self.window?.screen)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var topLeft: NSPoint? { window.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) } }
  var isKey: Bool { window?.isKeyWindow ?? false }
  var isVisible: Bool { window?.isVisible ?? false }

  func showNear(point: NSPoint) {
    guard let window else { return }
    caret = nil
    sizeToFit()
    let size = window.frame.size
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    let above = NSPoint(x: point.x - size.width / 2, y: point.y + 12 + size.height)
    let anchor =
      above.y <= (screen?.visibleFrame.maxY ?? above.y)
      ? above : NSPoint(x: above.x, y: point.y - 12)
    position(topLeft: anchor, screen: screen)
    window.orderFrontRegardless()
  }

  func place(near caret: CGRect) {
    self.caret = caret
    placedAbove = false
    sizeToFit()
    positionNearCaret()
    if window?.isVisible == false { window?.orderFrontRegardless() }
  }

  func update(content: AnyView, interactive: Bool) {
    let anchor = topLeft
    hostingView.rootView = content
    (window as? GrammarPanel)?.allowsKeyboardFocus = interactive
    sizeToFit()
    if caret != nil {
      positionNearCaret()
    } else if let anchor {
      let screen = window?.screen ?? NSScreen.screens.first { $0.frame.contains(anchor) }
      position(topLeft: anchor, screen: screen)
    }
  }

  func focus() {
    guard let panel = window as? GrammarPanel, panel.allowsKeyboardFocus else { return }
    let wasKey = panel.isKeyWindow
    panel.makeKeyAndOrderFront(nil)
    if !wasKey { panel.makeFirstResponder(nil) }
  }

  func resizeToFit() {
    let anchor = topLeft
    sizeToFit()
    if caret != nil {
      positionNearCaret()
    } else if let anchor {
      position(topLeft: anchor, screen: window?.screen)
    }
  }

  private func positionNearCaret() {
    guard let window, let caret else { return }
    let gap: CGFloat = 8
    let screen =
      NSScreen.screens.first { $0.frame.contains(CGPoint(x: caret.midX, y: caret.midY)) }
      ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .infinite
    // Judge the room below against a full review, not the small checking state, so the panel
    // does not jump above the caret once results arrive. Once above, it stays above.
    let expectedHeight = max(window.frame.height, 360)
    if !placedAbove, caret.minY - gap - expectedHeight < visible.minY { placedAbove = true }
    let top =
      placedAbove ? caret.maxY + gap + window.frame.height : caret.minY - gap
    position(topLeft: NSPoint(x: caret.minX - 24, y: top), screen: screen)
  }

  func dismiss() { window?.orderOut(nil) }

  private func sizeToFit() {
    hostingView.layoutSubtreeIfNeeded()
    let size = hostingView.fittingSize
    if size.width > 0, size.height > 0 { window?.setContentSize(size) }
  }

  private func position(topLeft: NSPoint, screen: NSScreen?) {
    guard let window else { return }
    let anchor =
      screen.map {
        Self.clampedTopLeft(topLeft, size: window.frame.size, visibleFrame: $0.visibleFrame)
      } ?? topLeft
    window.setFrameTopLeftPoint(anchor)
  }

  static func clampedTopLeft(_ point: NSPoint, size: NSSize, visibleFrame: NSRect) -> NSPoint {
    let available = visibleFrame.insetBy(dx: 4, dy: 4)
    return NSPoint(
      x: min(max(point.x, available.minX), max(available.minX, available.maxX - size.width)),
      y: max(min(point.y, available.maxY), min(available.maxY, available.minY + size.height)))
  }
}

struct GrammarPanelDragHandle: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { DragView() }
  func updateNSView(_ nsView: NSView, context: Context) {}

  private final class DragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
      window?.performDrag(with: event)
      (window as? GrammarPanel)?.constrainAfterDrag?()
    }
  }
}
