import AppKit
import Testing

@testable import SelectionBarCore

@Suite("Grammar verified paste")
@MainActor
struct GrammarClipboardTests {
  @Test("Clipboard is restored after a verified edit; validation precedes dispatch")
  func verifiedPaste() async throws {
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { board.releaseGlobally() }
    board.setString("original clipboard", forType: .string)
    var prepared = false
    var pasted = false
    try await SelectionBarClipboardService().replaceVerifiedText(
      with: "corrected",
      prepare: {
        prepared = true
        return true
      }, verify: { pasted }, pasteboard: board,
      postPaste: {
        #expect(prepared)
        #expect(board.string(forType: .string) == "corrected")
        pasted = true
        return true
      }, settle: {})
    #expect(board.string(forType: .string) == "original clipboard")
  }

  @Test("Stale targets never receive a paste; failed readback is not reported as success")
  func refusalAndFailure() async throws {
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { board.releaseGlobally() }
    board.setString("original clipboard", forType: .string)
    await #expect(throws: GrammarCheckError.changed) {
      try await SelectionBarClipboardService().replaceVerifiedText(
        with: "correction", prepare: { false }, verify: { true },
        pasteboard: board,
        postPaste: {
          Issue.record("Must not post a paste for a stale target")
          return true
        }, settle: {})
    }
    #expect(board.string(forType: .string) == "original clipboard")
    await #expect(throws: GrammarCheckError.applyFailed) {
      try await SelectionBarClipboardService().replaceVerifiedText(
        with: "correction", prepare: { true }, verify: { false },
        pasteboard: board, postPaste: { true }, settle: {})
    }
    #expect(board.string(forType: .string) == "original clipboard")
  }

  @Test("A concurrent user copy is retained")
  func concurrentCopy() async throws {
    let board = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    defer { board.releaseGlobally() }
    board.setString("old", forType: .string)
    try await SelectionBarClipboardService().replaceVerifiedText(
      with: "correction", prepare: { true }, verify: { true },
      pasteboard: board,
      postPaste: {
        board.clearContents()
        board.setString("user copy", forType: .string)
        return true
      }, settle: {})
    #expect(board.string(forType: .string) == "user copy")
  }
}
