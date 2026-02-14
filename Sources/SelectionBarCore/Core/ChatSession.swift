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

  private let selectedText: String
  private let sourceURL: String?
  private let client: SelectionBarOpenAIClient
  private let context: OpenAICompatibleCompletionContext
  private let bytesLoader: SelectionBarOpenAIClient.BytesLoader?
  private var streamTask: Task<Void, Never>?
  private var sourceReadContinuation: CheckedContinuation<Bool, Never>?

  /// Cached source file info (computed once on first use).
  private var cachedSourceInfo: SourceFileInfo?
  private var sourceInfoResolved = false

  /// Whether the source is a local file path (not a URL) that can be read.
  private var sourceIsFilePath: Bool {
    guard let sourceURL else { return false }
    return sourceURL.hasPrefix("/")
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

  init(
    selectedText: String,
    sourceURL: String? = nil,
    client: SelectionBarOpenAIClient,
    context: OpenAICompatibleCompletionContext,
    bytesLoader: SelectionBarOpenAIClient.BytesLoader? = nil
  ) {
    self.selectedText = selectedText
    self.sourceURL = sourceURL
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
        var apiMessages = self.buildAPIMessages()
        let tools: [ToolDefinition]? = self.sourceIsFilePath ? [ChatSession.readSourceTool] : nil
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
          logger.info("AI requested read_source — waiting for user approval")

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
            logger.info("User approved read_source")

            for tc in toolCalls {
              let result = self.readSourceLines(arguments: tc.function.arguments)
              logger.info("read_source returned \(result.count) chars")
              apiMessages.append(
                OpenAICompatibleCompletionRequest.Message(
                  role: "tool",
                  content: result,
                  toolCallId: tc.id
                ))
            }

            self.isReadingSource = false
          } else {
            logger.info("User declined read_source")
            for tc in toolCalls {
              apiMessages.append(
                OpenAICompatibleCompletionRequest.Message(
                  role: "tool",
                  content:
                    "The user declined to share the source file content. Please answer based on the selected text only.",
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

  // MARK: - Source file reading

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

  // MARK: - API message building

  private func buildAPIMessages() -> [OpenAICompatibleCompletionRequest.Message] {
    var apiMessages: [OpenAICompatibleCompletionRequest.Message] = []

    var systemPrompt =
      "The user has selected the following text. Answer questions about it, or help transform it as requested.\n\n---\n\(selectedText)\n---"
    if let sourceURL {
      systemPrompt += "\n\nSource: \(sourceURL)"
      if sourceIsFilePath, let info = resolveSourceInfo() {
        systemPrompt += "\nFile has \(info.totalLines) lines."
        if let line = info.selectionLine {
          systemPrompt += " The selected text is around line \(line)."
        }
        systemPrompt +=
          "\nUse the read_source tool with line_start and line_end to read specific lines. Start with a small range (~50 lines around the area of interest) and expand if needed."
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
