import AppKit
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("PasteboardSnapshot Tests")
struct PasteboardSnapshotTests {

  /// A throwaway pasteboard, isolated from `NSPasteboard.general`.
  private func makeScratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("SelectionBarTests.\(UUID().uuidString)"))
  }

  @Test("a snapshot of an untouched pasteboard is empty")
  func snapshotOfUntouchedPasteboardIsEmpty() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    let snapshot = PasteboardSnapshot(capturing: pasteboard)
    #expect(snapshot.isEmpty)
  }

  @Test("a snapshot of a cleared pasteboard is empty")
  func snapshotOfClearedPasteboardIsEmpty() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()

    let snapshot = PasteboardSnapshot(capturing: pasteboard)
    #expect(snapshot.isEmpty)
  }

  @Test("restoring an empty snapshot is a no-op and returns nil")
  func restoringEmptySnapshotIsNoOp() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    pasteboard.clearContents()
    pasteboard.setString("later contents", forType: .string)
    let changeCountBefore = pasteboard.changeCount

    #expect(snapshot.restore(to: pasteboard) == nil)
    #expect(pasteboard.changeCount == changeCountBefore)
    #expect(pasteboard.string(forType: .string) == "later contents")
  }

  @Test("a captured string survives a clobber and restore round-trip")
  func stringRoundTrip() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)

    let snapshot = PasteboardSnapshot(capturing: pasteboard)
    #expect(!snapshot.isEmpty)

    pasteboard.clearContents()
    pasteboard.setString("borrowed", forType: .string)
    #expect(pasteboard.string(forType: .string) == "borrowed")

    let changeCount = snapshot.restore(to: pasteboard)
    #expect(changeCount != nil)
    #expect(pasteboard.string(forType: .string) == "original")
  }

  @Test("every captured type is restored")
  func multipleTypesRoundTrip() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    let customType = NSPasteboard.PasteboardType("com.selectionbar.tests.custom")
    let customData = Data([0x01, 0x02, 0x03, 0xff])

    pasteboard.clearContents()
    pasteboard.setString("original text", forType: .string)
    pasteboard.setData(customData, forType: customType)

    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    pasteboard.clearContents()
    pasteboard.setString("clobbered", forType: .string)
    #expect(pasteboard.data(forType: customType) == nil)

    snapshot.restore(to: pasteboard)

    #expect(pasteboard.string(forType: .string) == "original text")
    #expect(pasteboard.data(forType: customType) == customData)
  }

  @Test("restoring returns the change count from clearing the pasteboard")
  func restoreReturnsChangeCount() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)

    let snapshot = PasteboardSnapshot(capturing: pasteboard)
    let restored = snapshot.restore(to: pasteboard)

    #expect(restored != nil)
    #expect(restored == pasteboard.changeCount)
  }

  @Test("a snapshot can be restored more than once")
  func snapshotIsReusable() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)
    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    for _ in 0..<3 {
      pasteboard.clearContents()
      pasteboard.setString("scratch", forType: .string)
      snapshot.restore(to: pasteboard)
      #expect(pasteboard.string(forType: .string) == "original")
    }
  }

  @Test("capturing does not disturb the pasteboard it reads")
  func capturingIsNonDestructive() {
    let pasteboard = makeScratchPasteboard()
    defer { pasteboard.releaseGlobally() }

    pasteboard.clearContents()
    pasteboard.setString("original", forType: .string)
    let changeCountBefore = pasteboard.changeCount

    _ = PasteboardSnapshot(capturing: pasteboard)

    #expect(pasteboard.changeCount == changeCountBefore)
    #expect(pasteboard.string(forType: .string) == "original")
  }

  @Test("multi-item clipboards survive a capture/restore round trip")
  func multiItemRoundTrip() {
    let pasteboard = NSPasteboard(name: .init("SelectionBarTests.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }

    let first = NSPasteboardItem()
    first.setString("one", forType: .string)
    let second = NSPasteboardItem()
    second.setString("two", forType: .string)
    let third = NSPasteboardItem()
    third.setString("three", forType: .string)
    pasteboard.clearContents()
    pasteboard.writeObjects([first, second, third])

    let snapshot = PasteboardSnapshot(capturing: pasteboard)

    pasteboard.clearContents()
    pasteboard.setString("clobbered", forType: .string)
    #expect(pasteboard.pasteboardItems?.count == 1)

    snapshot.restore(to: pasteboard)

    // Copying several files produces several items; collapsing them to one
    // would silently drop the rest.
    let restored = pasteboard.pasteboardItems ?? []
    #expect(restored.count == 3)
    #expect(restored.compactMap { $0.string(forType: .string) } == ["one", "two", "three"])
  }
}
