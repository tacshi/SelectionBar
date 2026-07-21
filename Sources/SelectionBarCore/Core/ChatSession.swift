import Foundation
import Observation
import PDFKit
import UniformTypeIdentifiers
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "ChatSession")

@MainActor
@Observable
public final class ChatSession {
  public private(set) var messages: [ChatMessage] = []
  public private(set) var isStreaming = false
  public private(set) var isReadingSource = false
  public private(set) var pendingSourceRead = false
  @ObservationIgnored
  public private(set) var currentStreamingContent = ""
  public var error: String?

  public enum SourceKind {
    case file
    case webPage
  }

  public var sourceKind: SourceKind? {
    if sourceIsFilePath { return .file }
    if sourceIsBrowserURL { return .webPage }
    return nil
  }

  private let selectedText: String
  private let sourceURL: String?
  private let sourceBundleID: String?
  private let client: SelectionBarOpenAIClient
  private let context: OpenAICompatibleCompletionContext
  private let bytesLoader: SelectionBarOpenAIClient.BytesLoader?
  private var streamTask: Task<Void, Never>?
  private var sourceReadContinuation: CheckedContinuation<Bool, Never>?

  /// Cached source file info (computed once on first use).
  private var cachedSourceInfo: SourceFileInfo?
  private var sourceInfoResolved = false

  /// Accumulated tool results from previous rounds, so the AI remembers what it already read.
  private(set) var sourceReadHistory: [String] = []

  /// Cached source content (file or page text, fetched once).
  private var cachedSourceContent: String?
  private var sourceContentResolved = false

  /// Whether the source is a local file path (not a URL) that can be read.
  private var sourceIsFilePath: Bool {
    guard let sourceURL else { return false }
    return sourceURL.hasPrefix("/")
  }

  /// Whether the source is a browser URL with a known browser that can provide page content.
  private var sourceIsBrowserURL: Bool {
    guard let sourceURL, let sourceBundleID else { return false }
    return (sourceURL.hasPrefix("http://") || sourceURL.hasPrefix("https://"))
      && SourceContextService.isBrowser(sourceBundleID)
  }

  /// Whether the source file is a PDF.
  private var sourceIsPDF: Bool {
    guard let sourceURL, sourceIsFilePath else { return false }
    let url = URL(fileURLWithPath: sourceURL)
    let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
    return contentType?.conforms(to: .pdf) == true
  }

  private static let readSourceTool = ToolDefinition(
    type: "function",
    function: .init(
      name: "read_source",
      description:
        "Read a range of lines from the source file. Use this when you need more context. You can call it multiple times to expand the range.",
      parameters: .init(
        type: "object",
        properties: [
          "line_start": .init(type: "integer", description: "Starting line number (1-based)"),
          "line_end": .init(type: "integer", description: "Ending line number (1-based)"),
        ],
        required: ["line_start", "line_end"]
      )
    )
  )

  private static let readPageTool = ToolDefinition(
    type: "function",
    function: .init(
      name: "read_page",
      description:
        "Read text content from the web page around the selected text. Returns surrounding context to help understand what the user selected.",
      parameters: .init(
        type: "object",
        properties: [
          "max_chars": .init(
            type: "integer",
            description: "Maximum characters to return (default 5000, max 20000)")
        ],
        required: []
      )
    )
  )

  private static let readPDFTool = ToolDefinition(
    type: "function",
    function: .init(
      name: "read_pdf_pages",
      description:
        "Read specific pages from the PDF document. Returns the text content of the requested pages.",
      parameters: .init(
        type: "object",
        properties: [
          "page_start": .init(type: "integer", description: "Starting page number (1-based)"),
          "page_end": .init(type: "integer", description: "Ending page number (1-based)"),
        ],
        required: ["page_start", "page_end"]
      )
    )
  )

  /// Optional callback invoked when streaming completes (success or error).
  var onStreamingComplete: (() -> Void)?

  init(
    selectedText: String,
    sourceURL: String? = nil,
    sourceBundleID: String? = nil,
    client: SelectionBarOpenAIClient,
    context: OpenAICompatibleCompletionContext,
    bytesLoader: SelectionBarOpenAIClient.BytesLoader? = nil,
    restoredMessages: [ChatMessage] = [],
    restoredSourceReadHistory: [String] = []
  ) {
    self.selectedText = selectedText
    self.sourceURL = sourceURL
    self.sourceBundleID = sourceBundleID
    self.client = client
    self.context = context
    self.bytesLoader = bytesLoader
    self.messages = restoredMessages
    self.sourceReadHistory = restoredSourceReadHistory
  }

  public func sendMessage(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard !isStreaming else { return }

    error = nil
    messages.append(ChatMessage(role: .user, content: text))

    let assistantMessage = ChatMessage(role: .assistant, content: "")
    messages.append(assistantMessage)
    // Track by id, not index: `reset()` and `restoreMessages()` can replace the
    // whole array while this task is suspended, and a stale index would either
    // write to the wrong message or trap.
    let assistantID = assistantMessage.id

    isStreaming = true
    currentStreamingContent = ""

    streamTask = Task { [weak self] in
      guard let self else { return }
      do {
        var apiMessages = await self.buildAPIMessages()
        let tools: [ToolDefinition]? = self.resolveTools()
        let maxToolRounds = 5

        for _ in 0..<maxToolRounds {
          let stream = self.client.streamCompletion(
            messages: apiMessages,
            tools: tools,
            context: self.context,
            temperature: 0.7,
            bytesLoader: self.bytesLoader
          )

          var toolCalls: [ToolCall] = []

          for try await event in stream {
            guard !Task.isCancelled else { break }
            switch event {
            case .content(let token):
              self.currentStreamingContent += token
              self.setContent(self.currentStreamingContent, forMessage: assistantID)
            case .toolCall(let tc):
              toolCalls.append(tc)
            }
          }

          guard !Task.isCancelled else { break }

          if toolCalls.isEmpty { break }

          // Ask user for permission
          self.pendingSourceRead = true
          logger.info("AI requested tool call — waiting for user approval")

          let approved = await withCheckedContinuation { continuation in
            self.sourceReadContinuation = continuation
          }
          self.pendingSourceRead = false

          guard !Task.isCancelled else { break }

          // Add assistant message with tool calls to conversation
          apiMessages.append(
            OpenAICompatibleCompletionRequest.Message(
              role: "assistant",
              content: self.currentStreamingContent,
              toolCalls: toolCalls
            ))

          if approved {
            self.isReadingSource = true
            logger.info("User approved source read")

            for tc in toolCalls {
              let result = await self.executeToolCall(tc)
              logger.info("\(tc.function.name) returned \(result.count) chars")
              self.appendSourceReadHistory(result)
              apiMessages.append(
                OpenAICompatibleCompletionRequest.Message(
                  role: "tool",
                  content: result,
                  toolCallId: tc.id
                ))
            }

            self.isReadingSource = false
          } else {
            logger.info("User declined source read")
            for tc in toolCalls {
              apiMessages.append(
                OpenAICompatibleCompletionRequest.Message(
                  role: "tool",
                  content:
                    "The user declined to share the source content. Please answer based on the selected text only.",
                  toolCallId: tc.id
                ))
            }
          }

          // Clear the pre-tool-call text so the follow-up response starts fresh
          self.currentStreamingContent = ""
          self.setContent("", forMessage: assistantID)
        }

        self.isStreaming = false
        self.streamTask = nil
        self.onStreamingComplete?()
      } catch {
        guard !Task.isCancelled else {
          self.isStreaming = false
          self.isReadingSource = false
          self.pendingSourceRead = false
          self.streamTask = nil
          return
        }
        self.error = error.localizedDescription
        self.isStreaming = false
        self.isReadingSource = false
        self.pendingSourceRead = false
        self.streamTask = nil
        // Remove empty assistant message on error
        if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
          self.messages[index].content.isEmpty
        {
          self.messages.remove(at: index)
        }
        self.onStreamingComplete?()
      }
    }
  }

  /// The whole history is re-sent in the system prompt on every turn and
  /// persisted with the session, so it has to stay bounded — otherwise a long
  /// conversation over a large file grows token cost and memory without limit.
  static let maxSourceReadHistoryCharacters = 60_000

  private func appendSourceReadHistory(_ entry: String) {
    sourceReadHistory.append(entry)
    var total = sourceReadHistory.reduce(0) { $0 + $1.count }
    while total > Self.maxSourceReadHistoryCharacters, sourceReadHistory.count > 1 {
      total -= sourceReadHistory.removeFirst().count
    }
  }

  private func setContent(_ content: String, forMessage id: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].content = content
  }

  public func approveSourceRead() {
    sourceReadContinuation?.resume(returning: true)
    sourceReadContinuation = nil
  }

  public func denySourceRead() {
    sourceReadContinuation?.resume(returning: false)
    sourceReadContinuation = nil
  }

  public func cancelStreaming() {
    sourceReadContinuation?.resume(returning: false)
    sourceReadContinuation = nil
    streamTask?.cancel()
    streamTask = nil
    isStreaming = false
    isReadingSource = false
    pendingSourceRead = false
  }

  public func retryLastMessage() {
    guard !isStreaming else { return }
    // Find the last user message and resend it
    guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }
    let text = lastUserMessage.content
    // Remove the failed user message so sendMessage re-appends it
    if let idx = messages.lastIndex(where: { $0.id == lastUserMessage.id }) {
      messages.remove(at: idx)
    }
    error = nil
    sendMessage(text)
  }

  public func reset() {
    cancelStreaming()
    messages.removeAll()
    currentStreamingContent = ""
    sourceReadHistory.removeAll()
    error = nil
  }

  public func restoreMessages(
    _ restoredMessages: [ChatMessage], sourceReadHistory restoredHistory: [String] = []
  ) {
    cancelStreaming()
    messages = restoredMessages
    currentStreamingContent = ""
    sourceReadHistory = restoredHistory
    error = nil
  }

  // MARK: - Tool resolution

  private func resolveTools() -> [ToolDefinition]? {
    switch sourceKind {
    case .file: [sourceIsPDF ? ChatSession.readPDFTool : ChatSession.readSourceTool]
    case .webPage: [ChatSession.readPageTool]
    case nil: nil
    }
  }

  private func executeToolCall(_ tc: ToolCall) async -> String {
    switch tc.function.name {
    case "read_source":
      return await readSourceLines(arguments: tc.function.arguments)
    case "read_pdf_pages":
      return await readPDFPages(arguments: tc.function.arguments)
    case "read_page":
      return await readPageExcerpt(arguments: tc.function.arguments)
    default:
      return "Error: Unknown tool '\(tc.function.name)'."
    }
  }

  // MARK: - Source content

  /// Fetches and caches the full source content (browser page only).
  private func getSourceContent() async -> String? {
    if sourceContentResolved { return cachedSourceContent }
    sourceContentResolved = true

    if case .webPage = sourceKind, let sourceBundleID {
      cachedSourceContent = await SourceContextService.readPageContent(bundleID: sourceBundleID)
    }

    return cachedSourceContent
  }

  // MARK: - File content reading

  private enum SourceFileInfo {
    case text(totalLines: Int, selectionLine: Int?)
    case pdf(totalPages: Int, selectionPage: Int?)
  }

  private func resolveSourceInfo() -> SourceFileInfo? {
    if sourceInfoResolved { return cachedSourceInfo }
    sourceInfoResolved = true

    guard let sourceURL, sourceIsFilePath else { return nil }

    if sourceIsPDF {
      guard let doc = PDFDocument(url: URL(fileURLWithPath: sourceURL)) else { return nil }
      let totalPages = doc.pageCount

      // Find page containing selected text
      var selectionPage: Int?
      let searchText = String(
        selectedText.prefix(200)
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      if !searchText.isEmpty {
        for i in 0..<totalPages {
          if let pageText = doc.page(at: i)?.string, pageText.contains(searchText) {
            selectionPage = i + 1
            break
          }
        }
      }

      let info = SourceFileInfo.pdf(totalPages: totalPages, selectionPage: selectionPage)
      cachedSourceInfo = info
      return info
    }

    // Text file
    guard let content = try? String(contentsOfFile: sourceURL, encoding: .utf8)
    else { return nil }

    let lines = content.components(separatedBy: .newlines)

    let firstSelectedLine =
      selectedText.components(separatedBy: .newlines).first?
      .trimmingCharacters(in: .whitespaces) ?? ""
    var selectionLine: Int?
    if !firstSelectedLine.isEmpty {
      for (idx, line) in lines.enumerated() {
        if line.contains(firstSelectedLine) {
          selectionLine = idx + 1
          break
        }
      }
    }

    let info = SourceFileInfo.text(totalLines: lines.count, selectionLine: selectionLine)
    cachedSourceInfo = info
    return info
  }

  // MARK: - Text file reading

  private struct ReadSourceArgs: Decodable {
    let lineStart: Int
    let lineEnd: Int

    enum CodingKeys: String, CodingKey {
      case lineStart = "line_start"
      case lineEnd = "line_end"
    }
  }

  private func readSourceLines(arguments: String) async -> String {
    guard let sourceURL, sourceIsFilePath else {
      return "Error: Source is not a readable file."
    }

    guard let range = ChatSession.parseSourceLineRange(from: arguments) else {
      return "Error: Invalid arguments. Provide line_start and line_end as integers."
    }

    // Reading and splitting a whole file is slow enough to freeze the UI on a
    // large log; ChatSession is @MainActor, so push it off.
    return await Task.detached(priority: .userInitiated) {
      guard let content = try? String(contentsOfFile: sourceURL, encoding: .utf8) else {
        return "Error: Could not read file."
      }
      let allLines = content.components(separatedBy: .newlines)
      return ChatSession.formatSourceLines(
        lineStart: range.start, lineEnd: range.end, allLines: allLines)
    }.value
  }

  // MARK: - PDF reading

  private struct ReadPDFArgs: Decodable {
    let pageStart: Int
    let pageEnd: Int

    enum CodingKeys: String, CodingKey {
      case pageStart = "page_start"
      case pageEnd = "page_end"
    }
  }

  private func readPDFPages(arguments: String) async -> String {
    guard let sourceURL, sourceIsFilePath else {
      return "Error: Source is not a readable file."
    }

    guard let range = ChatSession.parsePDFPageRange(from: arguments) else {
      return "Error: Invalid arguments. Provide page_start and page_end as integers."
    }

    // Extracting text from a large PDF blocks for seconds — keep it off the
    // main actor.
    return await Task.detached(priority: .userInitiated) {
      guard let doc = PDFDocument(url: URL(fileURLWithPath: sourceURL)) else {
        return "Error: Could not open PDF document."
      }
      return ChatSession.formatPDFPages(
        pageStart: range.start,
        pageEnd: range.end,
        totalPages: doc.pageCount,
        pageTextProvider: { doc.page(at: $0 - 1)?.string }
      )
    }.value
  }

  // MARK: - Web page reading

  private struct ReadPageArgs: Decodable {
    let maxChars: Int?

    enum CodingKeys: String, CodingKey {
      case maxChars = "max_chars"
    }
  }

  private func readPageExcerpt(arguments: String) async -> String {
    guard let content = await getSourceContent() else {
      return
        "Error: Could not read page content. The browser may not support JavaScript execution via AppleScript."
    }

    let maxChars = ChatSession.parseMaxChars(from: arguments)
    return ChatSession.extractPageExcerpt(
      content: content, selectedText: selectedText, maxChars: maxChars)
  }

  // MARK: - Testable static helpers

  /// Upper bound on a single tool result. `read_page` already clamps itself;
  /// the file and PDF readers need the same ceiling because whatever they
  /// return is replayed in the system prompt on every later turn.
  nonisolated static let maxToolResultCharacters = 20_000

  /// Parse `max_chars` from JSON arguments, defaulting to 5000 and clamping to [500, 20000].
  static func parseMaxChars(from arguments: String) -> Int {
    guard let data = arguments.data(using: .utf8),
      let args = try? JSONDecoder().decode(ReadPageArgs.self, from: data),
      let mc = args.maxChars
    else {
      return 5000
    }
    return min(max(mc, 500), 20_000)
  }

  /// Extract a page excerpt centered around the selected text, falling back to the start.
  static func extractPageExcerpt(content: String, selectedText: String, maxChars: Int) -> String {
    let totalChars = content.count

    let searchText = String(selectedText.prefix(200))
    if !searchText.isEmpty, let range = content.range(of: searchText) {
      let center = content.distance(from: content.startIndex, to: range.lowerBound)
      let halfRange = maxChars / 2
      let start = max(0, center - halfRange)
      let effectiveEnd = min(totalChars, start + maxChars)

      let startIdx = content.index(content.startIndex, offsetBy: start)
      let endIdx = content.index(content.startIndex, offsetBy: effectiveEnd)
      let excerpt = String(content[startIdx..<endIdx])

      return
        "Page content (\(totalChars) total chars, showing chars \(start)–\(effectiveEnd)):\n\(excerpt)"
    }

    // Fallback: return from start
    let excerpt = String(content.prefix(maxChars))
    return
      "Page content (\(totalChars) total chars, showing first \(excerpt.count) chars):\n\(excerpt)"
  }

  /// Parse `page_start` / `page_end` from JSON arguments.
  static func parsePDFPageRange(from arguments: String) -> (start: Int, end: Int)? {
    guard let data = arguments.data(using: .utf8),
      let args = try? JSONDecoder().decode(ReadPDFArgs.self, from: data)
    else {
      return nil
    }
    return (start: args.pageStart, end: args.pageEnd)
  }

  /// Format PDF pages with clamping and separator output.
  nonisolated static func formatPDFPages(
    pageStart: Int,
    pageEnd: Int,
    totalPages: Int,
    pageTextProvider: (Int) -> String?
  ) -> String {
    let start = max(1, pageStart)
    let end = min(totalPages, pageEnd)

    guard start <= end else {
      return "Error: page_start (\(pageStart)) must be <= page_end (\(pageEnd))."
    }

    var pages: [String] = []
    var characters = 0
    var lastPage = start
    var didTruncate = false
    for i in start...end {
      var pageText = pageTextProvider(i) ?? "(empty page)"
      // Clamp the page itself, not just the running total: a single scanned
      // page can be larger than the whole budget, and checking only after
      // appending would let it through untouched.
      let remaining = max(0, maxToolResultCharacters - characters)
      if pageText.count > remaining {
        pageText = String(pageText.prefix(remaining))
        didTruncate = true
      }
      pages.append("--- Page \(i) ---\n\(pageText)")
      characters += pageText.count
      lastPage = i
      // The whole history is replayed into every subsequent request, so an
      // unbounded read would blow up token cost and memory.
      if characters >= maxToolResultCharacters {
        didTruncate = didTruncate || i < end
        break
      }
    }

    let body = pages.joined(separator: "\n\n")
    if didTruncate || lastPage < end {
      return
        "Pages \(start)-\(lastPage) of \(totalPages) (truncated at \(maxToolResultCharacters) characters; request fewer pages for more detail):\n\(body)"
    }
    return "Pages \(start)-\(end) of \(totalPages):\n\(body)"
  }

  /// Parse `line_start` / `line_end` from JSON arguments.
  static func parseSourceLineRange(from arguments: String) -> (start: Int, end: Int)? {
    guard let data = arguments.data(using: .utf8),
      let args = try? JSONDecoder().decode(ReadSourceArgs.self, from: data)
    else {
      return nil
    }
    return (start: args.lineStart, end: args.lineEnd)
  }

  /// Format source lines with clamping and numbered output.
  nonisolated static func formatSourceLines(lineStart: Int, lineEnd: Int, allLines: [String])
    -> String
  {
    let start = max(1, lineStart)
    let end = min(allLines.count, lineEnd)

    guard start <= end else {
      return "Error: line_start (\(lineStart)) must be <= line_end (\(lineEnd))."
    }

    let slice = allLines[(start - 1)..<end]
    var numbered = ""
    var lastLine = start
    var didTruncate = false
    for (offset, line) in slice.enumerated() {
      let prefix = numbered.isEmpty ? "" : "\n"
      let entry = "\(prefix)\(start + offset):\(line)"
      // Clamp the line itself: one minified source line can exceed the whole
      // budget on its own, so checking only after appending lets it through.
      let remaining = max(0, maxToolResultCharacters - numbered.count)
      if entry.count > remaining {
        numbered += String(entry.prefix(remaining))
        lastLine = start + offset
        didTruncate = true
        break
      }
      numbered += entry
      lastLine = start + offset
      if numbered.count >= maxToolResultCharacters {
        didTruncate = didTruncate || (start + offset) < end
        break
      }
    }

    if didTruncate || lastLine < end {
      return
        "Lines \(start)-\(lastLine) of \(allLines.count) (truncated at \(maxToolResultCharacters) characters; request a narrower range for more detail):\n\(numbered)"
    }
    return "Lines \(start)-\(end) of \(allLines.count):\n\(numbered)"
  }

  // MARK: - API message building

  private func buildAPIMessages() async -> [OpenAICompatibleCompletionRequest.Message] {
    var apiMessages: [OpenAICompatibleCompletionRequest.Message] = []

    let contextDescription: String
    switch sourceKind {
    case .webPage:
      contextDescription = "from a web page"
    case .file, nil:
      contextDescription = ""
    }
    let contextSuffix = contextDescription.isEmpty ? "" : " \(contextDescription)"
    var systemPrompt =
      "The user has selected the following text\(contextSuffix). The conversation starts from this selected text — keep answers anchored to it. If you read additional source content, use it as supporting context for the selected text, not as the primary focus.\n\n---\n\(selectedText)\n---"

    if let sourceURL {
      systemPrompt += "\n\nSource: \(sourceURL)"

      let hasReadHistory = !sourceReadHistory.isEmpty

      switch sourceKind {
      case .file:
        if let info = resolveSourceInfo() {
          switch info {
          case .text(let totalLines, let selectionLine):
            systemPrompt += "\nFile has \(totalLines) lines."
            if let line = selectionLine {
              systemPrompt += " The selected text is around line \(line)."
            }
            if hasReadHistory {
              systemPrompt +=
                "\nYou have already read parts of this file (shown below). You can use the read_source tool to read additional lines if needed, but do not re-read content you already have."
            } else {
              systemPrompt +=
                "\nIf you need more context beyond the selected text, you can use the read_source tool with line_start and line_end to read specific lines. Only call it when the selected text is insufficient to answer the question."
            }
          case .pdf(let totalPages, let selectionPage):
            systemPrompt += "\nPDF document has \(totalPages) pages."
            if let page = selectionPage {
              systemPrompt += " The selected text is on page \(page)."
            }
            if hasReadHistory {
              systemPrompt +=
                "\nYou have already read parts of this document (shown below). You can use the read_pdf_pages tool to read additional pages if needed, but do not re-read content you already have."
            } else {
              systemPrompt +=
                "\nIf you need more context beyond the selected text, you can use the read_pdf_pages tool with page_start and page_end to read specific pages. Only call it when the selected text is insufficient to answer the question."
            }
          }
        }
      case .webPage:
        if hasReadHistory {
          systemPrompt +=
            "\nYou have already read parts of this web page (shown below). You can use the read_page tool to read more if needed, but do not re-read content you already have."
        } else {
          systemPrompt +=
            "\nYou have a read_page tool available to read the surrounding text content of this web page. Only use it when the user's question cannot be answered from the selected text alone — for example, when you need to understand what a pronoun refers to, what comes before/after the selection, or the broader topic being discussed. Do not call it if the selected text already provides enough context."
        }
      case nil:
        break
      }

      if hasReadHistory {
        systemPrompt += "\n\n--- Previously read content ---\n"
        systemPrompt += sourceReadHistory.joined(separator: "\n\n")
        systemPrompt += "\n--- End of previously read content ---"
      }
    }

    apiMessages.append(
      OpenAICompatibleCompletionRequest.Message(role: "system", content: systemPrompt))

    for message in messages {
      if message.role == .assistant && message.content.isEmpty {
        continue
      }
      apiMessages.append(
        OpenAICompatibleCompletionRequest.Message(
          role: message.role.rawValue,
          content: message.content
        ))
    }

    return apiMessages
  }
}
