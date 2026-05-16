import Foundation
import PDFKit
import UniformTypeIdentifiers

public struct SelectionBarActionSourceContext: Equatable, Sendable {
  public enum SourceKind: String, Sendable {
    case textFile = "Text File"
    case pdf = "PDF"
    case webPage = "Web Page"
    case unavailable = "Unavailable"
  }

  public let appName: String
  public let bundleID: String
  public let sourceURL: String
  public let sourceKind: SourceKind
  public let excerpt: String
  public let isAvailable: Bool

  public init(
    appName: String = "",
    bundleID: String = "",
    sourceURL: String = "",
    sourceKind: SourceKind = .unavailable,
    excerpt: String,
    isAvailable: Bool
  ) {
    self.appName = appName
    self.bundleID = bundleID
    self.sourceURL = sourceURL
    self.sourceKind = sourceKind
    self.excerpt = excerpt
    self.isAvailable = isAvailable
  }

  var formattedPromptBlock: String {
    var lines = ["Source Context:"]
    if !appName.isEmpty {
      lines.append("App: \(appName)")
    }
    if !bundleID.isEmpty {
      lines.append("Bundle ID: \(bundleID)")
    }
    if !sourceURL.isEmpty {
      lines.append("Source: \(sourceURL)")
    }
    lines.append("Kind: \(sourceKind.rawValue)")
    lines.append("")
    lines.append(excerpt)
    return lines.joined(separator: "\n")
  }
}

@MainActor
enum SelectionBarActionSourceContextResolver {
  static let maxContextCharacters = 8_000
  private static let textLineRadius = 40
  private static let pdfPageRadius = 1

  typealias PageContentReader = @Sendable (String) async -> String?

  static func resolve(
    selectedText: String,
    appName: String?,
    bundleID: String?,
    processID: pid_t?,
    pageContentReader: @escaping PageContentReader = { bundleID in
      await SourceContextService.readPageContent(bundleID: bundleID)
    }
  ) async -> SelectionBarActionSourceContext {
    let sourceURL = await SourceContextService.resolveSource(bundleID: bundleID, pid: processID)
    return await makeSnapshot(
      selectedText: selectedText,
      appName: appName,
      bundleID: bundleID,
      sourceURL: sourceURL,
      pageContentReader: pageContentReader
    )
  }

  static func makeSnapshot(
    selectedText: String,
    appName: String?,
    bundleID: String?,
    sourceURL: String?,
    pageContentReader: @escaping PageContentReader = { bundleID in
      await SourceContextService.readPageContent(bundleID: bundleID)
    }
  ) async -> SelectionBarActionSourceContext {
    let normalizedAppName = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalizedBundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalizedSourceURL = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !normalizedSourceURL.isEmpty else {
      return unavailable(
        appName: normalizedAppName,
        bundleID: normalizedBundleID,
        sourceURL: normalizedSourceURL,
        reason: "Source context unavailable: no readable source was detected."
      )
    }

    if isWebPageSource(normalizedSourceURL, bundleID: normalizedBundleID) {
      return await makeWebPageSnapshot(
        selectedText: selectedText,
        appName: normalizedAppName,
        bundleID: normalizedBundleID,
        sourceURL: normalizedSourceURL,
        pageContentReader: pageContentReader
      )
    }

    guard normalizedSourceURL.hasPrefix("/") else {
      return unavailable(
        appName: normalizedAppName,
        bundleID: normalizedBundleID,
        sourceURL: normalizedSourceURL,
        reason: "Source context unavailable: source is not a readable local file or web page."
      )
    }

    if isPDFSource(normalizedSourceURL) {
      return makePDFSnapshot(
        selectedText: selectedText,
        appName: normalizedAppName,
        bundleID: normalizedBundleID,
        sourceURL: normalizedSourceURL
      )
    }

    return makeTextFileSnapshot(
      selectedText: selectedText,
      appName: normalizedAppName,
      bundleID: normalizedBundleID,
      sourceURL: normalizedSourceURL
    )
  }

  private static func makeTextFileSnapshot(
    selectedText: String,
    appName: String,
    bundleID: String,
    sourceURL: String
  ) -> SelectionBarActionSourceContext {
    guard let content = try? String(contentsOfFile: sourceURL, encoding: .utf8) else {
      return unavailable(
        appName: appName,
        bundleID: bundleID,
        sourceURL: sourceURL,
        reason: "Source context unavailable: could not read the source file."
      )
    }

    let lines = content.components(separatedBy: .newlines)
    let selectionLine = findSelectionLine(selectedText: selectedText, lines: lines)
    let lineStart: Int
    let lineEnd: Int
    if let selectionLine {
      lineStart = max(1, selectionLine - textLineRadius)
      lineEnd = min(lines.count, selectionLine + textLineRadius)
    } else {
      lineStart = 1
      lineEnd = min(lines.count, (textLineRadius * 2) + 1)
    }

    let excerpt = ChatSession.formatSourceLines(
      lineStart: lineStart,
      lineEnd: lineEnd,
      allLines: lines
    )

    return SelectionBarActionSourceContext(
      appName: appName,
      bundleID: bundleID,
      sourceURL: sourceURL,
      sourceKind: .textFile,
      excerpt: capped(excerpt),
      isAvailable: true
    )
  }

  private static func makePDFSnapshot(
    selectedText: String,
    appName: String,
    bundleID: String,
    sourceURL: String
  ) -> SelectionBarActionSourceContext {
    guard let document = PDFDocument(url: URL(fileURLWithPath: sourceURL)) else {
      return unavailable(
        appName: appName,
        bundleID: bundleID,
        sourceURL: sourceURL,
        reason: "Source context unavailable: could not open the PDF document."
      )
    }

    let selectionPage = findSelectionPage(selectedText: selectedText, document: document)
    let pageStart: Int
    let pageEnd: Int
    if let selectionPage {
      pageStart = max(1, selectionPage - pdfPageRadius)
      pageEnd = min(document.pageCount, selectionPage + pdfPageRadius)
    } else {
      pageStart = 1
      pageEnd = min(document.pageCount, (pdfPageRadius * 2) + 1)
    }

    let excerpt = ChatSession.formatPDFPages(
      pageStart: pageStart,
      pageEnd: pageEnd,
      totalPages: document.pageCount,
      pageTextProvider: { document.page(at: $0 - 1)?.string }
    )

    return SelectionBarActionSourceContext(
      appName: appName,
      bundleID: bundleID,
      sourceURL: sourceURL,
      sourceKind: .pdf,
      excerpt: capped(excerpt),
      isAvailable: true
    )
  }

  private static func makeWebPageSnapshot(
    selectedText: String,
    appName: String,
    bundleID: String,
    sourceURL: String,
    pageContentReader: @escaping PageContentReader
  ) async -> SelectionBarActionSourceContext {
    guard let content = await pageContentReader(bundleID) else {
      return unavailable(
        appName: appName,
        bundleID: bundleID,
        sourceURL: sourceURL,
        reason:
          "Source context unavailable: could not read page text. Check browser Automation permission."
      )
    }

    let excerpt = ChatSession.extractPageExcerpt(
      content: content,
      selectedText: selectedText,
      maxChars: maxContextCharacters
    )

    return SelectionBarActionSourceContext(
      appName: appName,
      bundleID: bundleID,
      sourceURL: sourceURL,
      sourceKind: .webPage,
      excerpt: capped(excerpt),
      isAvailable: true
    )
  }

  private static func unavailable(
    appName: String,
    bundleID: String,
    sourceURL: String,
    reason: String
  ) -> SelectionBarActionSourceContext {
    SelectionBarActionSourceContext(
      appName: appName,
      bundleID: bundleID,
      sourceURL: sourceURL,
      sourceKind: .unavailable,
      excerpt: reason,
      isAvailable: false
    )
  }

  private static func findSelectionLine(selectedText: String, lines: [String]) -> Int? {
    let searchLine =
      selectedText.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty } ?? ""
    guard !searchLine.isEmpty else { return nil }

    for (index, line) in lines.enumerated() where line.contains(searchLine) {
      return index + 1
    }
    return nil
  }

  private static func findSelectionPage(selectedText: String, document: PDFDocument) -> Int? {
    let searchText = String(selectedText.prefix(200))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !searchText.isEmpty else { return nil }

    for pageIndex in 0..<document.pageCount {
      if let pageText = document.page(at: pageIndex)?.string, pageText.contains(searchText) {
        return pageIndex + 1
      }
    }
    return nil
  }

  private static func isWebPageSource(_ sourceURL: String, bundleID: String) -> Bool {
    (sourceURL.hasPrefix("http://") || sourceURL.hasPrefix("https://"))
      && SourceContextService.isBrowser(bundleID)
  }

  private static func isPDFSource(_ sourceURL: String) -> Bool {
    let url = URL(fileURLWithPath: sourceURL)
    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    return contentType?.conforms(to: .pdf) == true
  }

  private static func capped(_ text: String) -> String {
    guard text.count > maxContextCharacters else { return text }
    return String(text.prefix(maxContextCharacters))
  }
}
