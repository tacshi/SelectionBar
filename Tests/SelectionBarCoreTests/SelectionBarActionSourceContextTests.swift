import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarActionSourceContext Tests")
struct SelectionBarActionSourceContextTests {
  @Test("text file source context returns bounded lines around selection")
  func textFileSourceContextUsesBoundedSelectionExcerpt() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SelectionBarSourceContextTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let fileURL = directory.appendingPathComponent("sample.txt")
    let lines = (1...120).map { index in
      index == 60 ? "line 60 selected target" : "line \(index)"
    }
    try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)

    let snapshot = await SelectionBarActionSourceContextResolver.makeSnapshot(
      selectedText: "selected target",
      appName: "TextEdit",
      bundleID: "com.apple.TextEdit",
      sourceURL: fileURL.path
    )

    #expect(snapshot.isAvailable)
    #expect(snapshot.sourceKind == .textFile)
    #expect(snapshot.appName == "TextEdit")
    #expect(snapshot.bundleID == "com.apple.TextEdit")
    #expect(snapshot.sourceURL == fileURL.path)
    #expect(snapshot.excerpt.contains("Lines 20-100 of 120"))
    #expect(snapshot.excerpt.contains("60:line 60 selected target"))
    #expect(!snapshot.excerpt.contains("19:line 19"))
    #expect(!snapshot.excerpt.contains("101:line 101"))
  }

  @Test("source context falls back to unavailable snapshot without source")
  func unavailableSourceContextWithoutSource() async {
    let snapshot = await SelectionBarActionSourceContextResolver.makeSnapshot(
      selectedText: "selected",
      appName: "Preview",
      bundleID: "com.apple.Preview",
      sourceURL: nil
    )

    #expect(!snapshot.isAvailable)
    #expect(snapshot.sourceKind == .unavailable)
    #expect(snapshot.appName == "Preview")
    #expect(snapshot.bundleID == "com.apple.Preview")
    #expect(snapshot.formattedPromptBlock.contains("Source context unavailable"))
  }
}
