import AppKit
import SwiftUI

/// NSHostingView with a truly transparent backing layer.
private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool { false }

  required init(rootView: Content) {
    super.init(rootView: rootView)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()
    super.draw(dirtyRect)
  }

  @available(*, unavailable)
  required init(rootView: Content, ignoreSafeArea: Bool) {
    fatalError("init(rootView:ignoreSafeArea:) has not been implemented")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

/// Content view that never paints an opaque fallback background.
private final class ClearContainerView: NSView {
  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    dirtyRect.fill()
    super.draw(dirtyRect)
  }
}

/// A panel that doesn't activate the app when clicked or steal focus
private class SelectionBarPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Window controller for the floating selection bar popup
@MainActor
public class SelectionBarWindowController: NSWindowController {
  private let barHeight: CGFloat = 40
  private let barOffset: CGFloat = 12  // Distance above mouse
  private let windowEdgeInset: CGFloat = 4
  private let hostingView: NSHostingView<AnyView>

  public init(contentView: some View) {
    let hostingView = TransparentHostingView(rootView: AnyView(contentView))
    hostingView.sizingOptions = [.intrinsicContentSize]
    self.hostingView = hostingView

    let window = SelectionBarPanel(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    window.isOpaque = false
    window.backgroundColor = .clear
    // Keep shadow rendering in SwiftUI to avoid heavy double-border artifacts.
    window.hasShadow = false
    window.level = .popUpMenu
    window.ignoresMouseEvents = false  // Must accept button clicks
    window.isMovableByWindowBackground = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let containerView = ClearContainerView(frame: window.contentRect(forFrameRect: window.frame))
    containerView.wantsLayer = true
    containerView.layer?.backgroundColor = NSColor.clear.cgColor

    hostingView.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(hostingView)
    NSLayoutConstraint.activate([
      hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
    ])

    window.contentView = containerView

    super.init(window: window)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Public Methods

  /// Show the bar near the given screen point (typically mouse location)
  public func showNear(point: NSPoint) {
    guard let window = window else { return }

    let contentSize = sizeToFitContent()

    // Position above the mouse, centered horizontally
    var origin = NSPoint(
      x: point.x - contentSize.width / 2,
      y: point.y + barOffset
    )

    if let screen = preferredScreen(for: point) {
      let visibleFrame = screen.visibleFrame
      if origin.y + contentSize.height > visibleFrame.maxY {
        // If bar would go above screen top, show below mouse instead.
        origin.y = point.y - contentSize.height - barOffset
      }
      origin = clampedOrigin(origin, contentSize: contentSize, on: screen)
    }

    window.setFrameOrigin(origin)
    window.orderFrontRegardless()
  }

  /// Show the window at a fixed origin while sizing to SwiftUI content first.
  public func show(atOrigin origin: NSPoint) {
    guard let window = window else { return }
    let contentSize = sizeToFitContent()
    let clamped =
      if let screen = preferredScreen(for: origin) {
        clampedOrigin(origin, contentSize: contentSize, on: screen)
      } else {
        origin
      }
    window.setFrameOrigin(clamped)
    window.orderFrontRegardless()
  }

  /// Replace the SwiftUI content without recreating the window.
  public func update(contentView: some View) {
    hostingView.rootView = AnyView(contentView)
    _ = sizeToFitContent()
  }

  public var currentOrigin: NSPoint? {
    window?.frame.origin
  }

  public func dismiss() {
    window?.orderOut(nil)
  }

  @discardableResult
  private func sizeToFitContent() -> NSSize {
    guard let window = window else {
      return NSSize(width: 300, height: barHeight)
    }

    // Let SwiftUI calculate intrinsic size.
    hostingView.layoutSubtreeIfNeeded()
    let contentSize =
      hostingView.fittingSize == .zero
      ? NSSize(width: 300, height: barHeight)
      : hostingView.fittingSize
    window.setContentSize(contentSize)
    return contentSize
  }

  private func preferredScreen(for point: NSPoint) -> NSScreen? {
    NSScreen.screens.first(where: { $0.visibleFrame.contains(point) || $0.frame.contains(point) })
      ?? NSScreen.main
  }

  private func clampedOrigin(_ origin: NSPoint, contentSize: NSSize, on screen: NSScreen) -> NSPoint
  {
    let visibleFrame = screen.visibleFrame.insetBy(dx: windowEdgeInset, dy: windowEdgeInset)
    var clamped = origin

    let maxX = visibleFrame.maxX - contentSize.width
    let maxY = visibleFrame.maxY - contentSize.height

    if maxX < visibleFrame.minX {
      clamped.x = visibleFrame.minX
    } else {
      clamped.x = min(max(clamped.x, visibleFrame.minX), maxX)
    }

    if maxY < visibleFrame.minY {
      clamped.y = visibleFrame.minY
    } else {
      clamped.y = min(max(clamped.y, visibleFrame.minY), maxY)
    }

    return clamped
  }
}
