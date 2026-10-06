import AppKit
import SwiftUI
import Testing

@testable import SelectionBarCore

@Suite("Grammar presentation")
@MainActor
struct GrammarPresentationTests {
  @Test("A short review is compact and content growth preserves the native window position")
  func reviewLayout() async throws {
    _ = NSApplication.shared
    let state = GrammarReviewState()
    state.phase = .ready
    state.sourceCanApply = true
    state.originalText = "He are here. They is ready."
    state.suggestions = [
      GrammarSuggestion(
        id: UUID(), original: state.originalText,
        replacement: "He is here. They are ready.", category: .correctness,
        explanation: "Use “is” with “He” and “are” with “They”.",
        range: NSRange(location: 0, length: state.originalText.utf16.count))
    ]
    let view = GrammarReviewView(
      state: state, profileChanged: { _ in }, accept: { _ in },
      dismiss: { _ in }, applyAll: {}, undo: {}, copy: {}, retry: {}, recheck: {},
      settings: {}, enableClipboard: {}, close: {})
    let controller = GrammarWindowController(content: AnyView(view))
    let window = try #require(controller.window)
    let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
    window.setFrameTopLeftPoint(NSPoint(x: frame.minX + 30, y: frame.maxY - 30))
    for _ in 0..<6 {
      try await Task.sleep(for: .milliseconds(25))
      controller.resizeToFit()
    }
    let firstHeight = window.frame.height
    let anchor = controller.topLeft
    #expect(firstHeight > 160)
    #expect(firstHeight < 340)
    try exportPreview(window, name: "grammar-panel")
    state.suggestions = (0..<5).map { index in
      GrammarSuggestion(
        id: UUID(), original: "Example \(index) is incorrect.",
        replacement: "Example \(index) is correct.",
        category: .clarity, explanation: "A shorter explanation.",
        range: NSRange(location: 0, length: 1))
    }
    for _ in 0..<6 {
      try await Task.sleep(for: .milliseconds(25))
      controller.resizeToFit()
    }
    #expect(window.frame.height > firstHeight)
    #expect(window.frame.height < 500)
    #expect(controller.topLeft == anchor)
    try exportPreview(window, name: "grammar-panel-multiple")
    let expandedHeight = window.frame.height
    state.suggestions.removeLast()
    for _ in 0..<3 {
      try await Task.sleep(for: .milliseconds(25))
      controller.resizeToFit()
    }
    #expect(window.frame.height == expandedHeight)
  }

  private func exportPreview(_ window: NSWindow, name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["SELECTIONBAR_GRAMMAR_PREVIEW_DIR"],
      let view = window.contentView,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
    else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try data.write(to: URL(fileURLWithPath: directory).appending(path: "\(name).png"))
  }

  @Test("Native panel updates preserve the top-left corner while changing content size")
  func nativePanelGeometry() throws {
    _ = NSApplication.shared
    let controller = GrammarWindowController(
      content: AnyView(Text("Checking").frame(width: 440, height: 200)))
    let window = try #require(controller.window)
    controller.update(
      content: AnyView(Text("Checking").frame(width: 440, height: 200)), interactive: false)
    let frame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
    window.setFrameTopLeftPoint(NSPoint(x: frame.minX + 20, y: frame.maxY - 20))
    let before = controller.topLeft
    #expect(!window.canBecomeKey)
    controller.update(
      content: AnyView(Text("Results").frame(width: 440, height: 400)), interactive: true)
    #expect(controller.topLeft == before)
    #expect(window.canBecomeKey)
    #expect(!window.isVisible)
    controller.update(
      content: AnyView(Text("Completed").frame(width: 440, height: 160)), interactive: true)
    #expect(controller.topLeft == before)
  }

  @Test("Panel bounds remain inside screens including monitors with negative coordinates")
  func screenBounds() {
    let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
    let size = NSSize(width: 440, height: 450)
    let result = GrammarWindowController.clampedTopLeft(
      NSPoint(x: -10, y: 10), size: size, visibleFrame: screen)
    #expect(result.x == -444)
    #expect(result.y == 454)
    let rect = NSRect(
      x: result.x, y: result.y - size.height, width: size.width, height: size.height)
    #expect(screen.contains(rect))
  }

  @Test("Inline differences retain common context and handle Unicode and deletions")
  func differences() {
    let difference = GrammarTextDifference(
      original: "👩‍💻 They is ready.", replacement: "👩‍💻 They are ready.")
    #expect(difference.original.map(\.text).joined() == "👩‍💻 They is ready.")
    #expect(difference.replacement.map(\.text).joined() == "👩‍💻 They are ready.")
    #expect(difference.original.filter(\.changed).map(\.text).joined() == "is")
    #expect(difference.replacement.filter(\.changed).map(\.text).joined() == "are")
    let multiple = GrammarTextDifference(
      original: "He are here. They is ready.", replacement: "He is here. They are ready.")
    #expect(!multiple.replacement.filter(\.changed).map(\.text).joined().contains("here"))
    let chinese = GrammarTextDifference(original: "我喜欢苹果", replacement: "我喜欢香蕉")
    #expect(chinese.replacement.filter(\.changed).map(\.text).joined() == "香蕉")
    let deletion = GrammarTextDifference(original: "very clear", replacement: "clear")
    #expect(deletion.original.filter(\.changed).map(\.text).joined() == "very ")
    #expect(deletion.replacement.allSatisfy { !$0.changed })
    let empty = GrammarTextDifference(original: "", replacement: "hello")
    #expect(empty.replacement.filter(\.changed).map(\.text).joined() == "hello")
  }
}
