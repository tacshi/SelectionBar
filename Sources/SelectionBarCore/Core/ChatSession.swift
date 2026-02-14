import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.selectionbar", category: "ChatSession")

@MainActor
@Observable
public final class ChatSession {
  public private(set) var messages: [ChatMessage] = []
  public private(set) var isStreaming = false
  public private(set) var isReadingSource = false
  public private(set) var pendingSourceRead = false
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

  /// Whether the source can be read (file or browser page).
  private var sourceIsReadable: Bool {
    sourceIsFilePath || sourceIsBrowserURL
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

  init(
    selectedText: String,
    sourceURL: String? = nil,
    sourceBundleID: String? = nil,
    client: SelectionBarOpenAIClient,
    context: OpenAICompatibleCompletionContext,
    bytesLoader: SelectionBarOpenAIClient.BytesLoader? = nil
  ) {
    self.selectedText = selectedText
    self.sourceURL = sourceURL
    self.sourceBundleID = sourceBundleID
    self.client = client
    self.context = context
    self.bytesLoader = bytesLoader
  }

  public func sendMessage(_ text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard !isStreaming else { return }

    error = nil
    messages.append(ChatMessage(role: .user, content: text))

    let assistantMessage = ChatMessage(role: .assistant, content: "")
    messages.append(assistantMessage)
    let assistantIndex = messages.count - 1

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
              self.messages[assistantIndex].content = self.currentStreamingContent
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
          self.messages[assistantIndex].content = ""
        }

        self.isStreaming = false
        self.streamTask = nil
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
        if self.messages[assistantIndex].content.isEmpty {
          self.messages.remove(at: assistantIndex)
        }
      }
    }
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

  public func reset() {
    cancelStreaming()
    messages.removeAll()
    currentStreamingContent = ""
    error = nil
  }

  // MARK: - Tool resolution

  private func resolveTools() -> [ToolDefinition]? {
    switch sourceKind {
    case .file: [ChatSession.readSourceTool]
    case .webPage: [ChatSession.readPageTool]
    case nil: nil
    }
  }

  private func executeToolCall(_ tc: ToolCall) async -> String {
    switch tc.function.name {
    case "read_source":
      return readSourceLines(arguments: tc.function.arguments)
    case "read_page":
      return await readPageExcerpt(arguments: tc.function.arguments)
    default:
      return "Error: Unknown tool '\(tc.function.name)'."
    }
  }

  // MARK: - Source content

  /// Fetches and caches the full source content (file or browser page).
  private func getSourceContent() async -> String? {
    if sourceContentResolved { return cachedSourceContent }
    sourceContentResolved = true

    switch sourceKind {
    case .file:
      if let sourceURL {
        cachedSourceContent = try? String(contentsOfFile: sourceURL, encoding: .utf8)
      }
    case .webPage:
      if let sourceBundleID {
        cachedSourceContent = await SourceContextService.readPageContent(bundleID: sourceBundleID)
      }
    case nil:
      break
    }

    return cachedSourceContent
  }

  // MARK: - File source reading

  private struct SourceFileInfo {
    let totalLines: Int
    let selectionLine: Int?
  }

  private struct ReadSourceArgs: Decodable {
    let lineStart: Int
    let lineEnd: Int

    enum CodingKeys: String, CodingKey {
      case lineStart = "line_start"
      case lineEnd = "line_end"
    }
  }

  private func resolveSourceInfo() -> SourceFileInfo? {
    if sourceInfoResolved { return cachedSourceInfo }
    sourceInfoResolved = true

    guard let sourceURL, sourceURL.hasPrefix("/"),
      let content = try? String(contentsOfFile: sourceURL, encoding: .utf8)
    else { return nil }

    let lines = content.components(separatedBy: .newlines)

    // Find line where selected text starts
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

    let info = SourceFileInfo(totalLines: lines.count, selectionLine: selectionLine)
    cachedSourceInfo = info
    return info
  }

  private func readSourceLines(arguments: String) -> String {
    guard let sourceURL, sourceURL.hasPrefix("/") else {
      return "Error: Source is not a readable file."
    }

    do {
      let content = try String(contentsOfFile: sourceURL, encoding: .utf8)
      let allLines = content.components(separatedBy: .newlines)

      guard let data = arguments.data(using: .utf8),
        let args = try? JSONDecoder().decode(ReadSourceArgs.self, from: data)
      else {
        return "Error: Invalid arguments. Provide line_start and line_end as integers."
      }

      let start = max(1, args.lineStart)
      let end = min(allLines.count, args.lineEnd)

      guard start <= end else {
        return "Error: line_start (\(args.lineStart)) must be <= line_end (\(args.lineEnd))."
      }

      let slice = allLines[(start - 1)..<end]
      let numbered = slice.enumerated().map { offset, line in
        "\(start + offset):\(line)"
      }.joined(separator: "\n")

      return "Lines \(start)-\(end) of \(allLines.count):\n\(numbered)"
    } catch {
      return "Error reading file: \(error.localizedDescription)"
    }
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

    let maxChars: Int
    if let data = arguments.data(using: .utf8),
      let args = try? JSONDecoder().decode(ReadPageArgs.self, from: data),
      let mc = args.maxChars
    {
      maxChars = min(max(mc, 500), 20000)
    } else {
      maxChars = 5000
    }

    let totalChars = content.count

    // Try to center around the selected text
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
      "The user has selected the following text\(contextSuffix). Answer questions about it, or help transform it as requested.\n\n---\n\(selectedText)\n---"

    if let sourceURL {
      systemPrompt += "\n\nSource: \(sourceURL)"

      switch sourceKind {
      case .file:
        if let info = resolveSourceInfo() {
          systemPrompt += "\nFile has \(info.totalLines) lines."
          if let line = info.selectionLine {
            systemPrompt += " The selected text is around line \(line)."
          }
          systemPrompt +=
            "\nUse the read_source tool with line_start and line_end to read specific lines. Start with a small range (~50 lines around the area of interest) and expand if needed."
        }
      case .webPage:
        systemPrompt +=
          "\nIMPORTANT: You have a read_page tool to read the surrounding text content of this web page. When the user's question requires understanding the context around the selected text (e.g. what a pronoun refers to, what comes before/after, or the topic being discussed), you MUST call read_page first before answering. You can specify max_chars to control how much text is returned (default 5000)."
      case nil:
        break
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
