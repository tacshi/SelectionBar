import AppKit

/// Screen positions (AppKit coordinates) of each suggestion's text in the source editor.
struct GrammarUnderlineLayout: Equatable {
  struct Mark: Equatable {
    let id: UUID
    let category: GrammarSuggestionCategory
    /// One rect per visual line the suggestion spans, already clipped to `visibleFrame`.
    let rects: [CGRect]
  }

  /// The part of the editor that is on screen; underlines never draw outside it.
  let visibleFrame: CGRect
  let marks: [Mark]

  /// Hit targets extend below the text so a click on the squiggle itself counts.
  func mark(at point: CGPoint) -> UUID? {
    marks.first { mark in
      mark.rects.contains { $0.insetBy(dx: -1, dy: -3).contains(point) }
    }?.id
  }
}

@MainActor
protocol GrammarUnderlinePresenting: AnyObject {
  func show(_ layout: GrammarUnderlineLayout, highlighted: UUID?)
  func highlight(_ id: UUID?)
  func hide()
}

/// A click-through window over the source editor that draws Grammarly-style squiggles.
@MainActor
final class GrammarUnderlineOverlay: GrammarUnderlinePresenting {
  /// Squiggles hang slightly below the last visible line.
  private static let bottomMargin: CGFloat = 4
  private var panel: NSPanel?
  private var view: GrammarUnderlineView?

  func show(_ layout: GrammarUnderlineLayout, highlighted: UUID?) {
    let frame = layout.visibleFrame.insetBy(dx: 0, dy: -Self.bottomMargin)
    guard frame.width > 0, frame.height > 0, !layout.marks.isEmpty else {
      hide()
      return
    }
    let panel = panel ?? makePanel()
    view?.origin = frame.origin
    view?.marks = layout.marks
    view?.highlighted = highlighted
    if panel.frame != frame { panel.setFrame(frame, display: false) }
    view?.needsDisplay = true
    if !panel.isVisible { panel.orderFrontRegardless() }
  }

  func highlight(_ id: UUID?) {
    guard let view, view.highlighted != id else { return }
    view.highlighted = id
    view.needsDisplay = true
  }

  func hide() { panel?.orderOut(nil) }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.identifier = NSUserInterfaceItemIdentifier("SelectionBar.GrammarUnderlines")
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    // Above the source editor, below the review panel.
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.setAccessibilityElement(false)
    let view = GrammarUnderlineView()
    panel.contentView = view
    self.panel = panel
    self.view = view
    return panel
  }
}

private final class GrammarUnderlineView: NSView {
  var origin = CGPoint.zero
  var marks: [GrammarUnderlineLayout.Mark] = []
  var highlighted: UUID?

  override var isFlipped: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    for mark in marks {
      let color = Self.color(for: mark.category)
      for screenRect in mark.rects {
        let rect = screenRect.offsetBy(dx: -origin.x, dy: -origin.y)
        if mark.id == highlighted {
          color.withAlphaComponent(0.18).setFill()
          NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
        Self.squiggle(under: rect, color: color)
      }
    }
  }

  static func color(for category: GrammarSuggestionCategory) -> NSColor {
    switch category {
    case .correctness: .systemRed
    case .clarity: .systemBlue
    case .tone: .systemPurple
    }
  }

  private static func squiggle(under rect: CGRect, color: NSColor) {
    let amplitude: CGFloat = 1.25
    let period: CGFloat = 4
    let baseline = rect.minY - 0.5
    let path = NSBezierPath()
    path.lineWidth = 1.4
    path.lineCapStyle = .round
    path.move(to: CGPoint(x: rect.minX, y: baseline))
    var x = rect.minX
    var up = true
    while x < rect.maxX {
      let next = min(x + period / 2, rect.maxX)
      path.curve(
        to: CGPoint(x: next, y: baseline),
        controlPoint1: CGPoint(x: x + (next - x) / 2, y: baseline + (up ? amplitude : -amplitude)),
        controlPoint2: CGPoint(x: x + (next - x) / 2, y: baseline + (up ? amplitude : -amplitude)))
      x = next
      up.toggle()
    }
    color.withAlphaComponent(0.9).setStroke()
    path.stroke()
  }
}
