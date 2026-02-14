import Foundation

enum ChatStreamEvent: Sendable {
  case content(String)
  case toolCall(ToolCall)
}

extension SelectionBarOpenAIClient {
  typealias BytesLoader =
    @Sendable (URLRequest) async throws -> (
      URLSession.AsyncBytes, URLResponse
    )

  func streamCompletion(
    messages: [OpenAICompatibleCompletionRequest.Message],
    tools: [ToolDefinition]? = nil,
    context: OpenAICompatibleCompletionContext,
    temperature: Double,
    bytesLoader: BytesLoader? = nil
  ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let url = context.baseURL.appending(path: "chat/completions")
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.timeoutInterval = 120
          request.setValue("Bearer \(context.apiKey)", forHTTPHeaderField: "Authorization")
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")

          for (header, value) in context.extraHeaders {
            request.setValue(value, forHTTPHeaderField: header)
          }

          var body = OpenAICompatibleCompletionRequest(
            model: context.modelId,
            messages: messages,
            temperature: temperature
          )
          body.stream = true
          body.tools = tools
          request.httpBody = try JSONEncoder().encode(body)

          let loader = bytesLoader ?? defaultBytesLoader
          let (bytes, response) = try await loader(request)

          if let httpResponse = response as? HTTPURLResponse,
            !(200...299).contains(httpResponse.statusCode)
          {
            var errorBody = ""
            for try await line in bytes.lines {
              errorBody += line
            }
            throw SelectionBarError.httpError(httpResponse.statusCode, errorBody)
          }

          var accumulatedToolCalls: [Int: (id: String, name: String, arguments: String)] = [:]

          for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            if payload == "[DONE]" {
              break
            }

            guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(OpenAIStreamingChunk.self, from: data)
            else {
              continue
            }

            let choice = chunk.choices.first

            if let content = choice?.delta.content, !content.isEmpty {
              continuation.yield(.content(content))
            }

            if let deltas = choice?.delta.toolCalls {
              for delta in deltas {
                let idx = delta.index ?? 0
                if let id = delta.id {
                  accumulatedToolCalls[idx] = (id: id, name: "", arguments: "")
                }
                if var tc = accumulatedToolCalls[idx] {
                  if let name = delta.function?.name {
                    tc.name += name
                  }
                  if let args = delta.function?.arguments {
                    tc.arguments += args
                  }
                  accumulatedToolCalls[idx] = tc
                }
              }
            }
          }

          for (_, tc) in accumulatedToolCalls.sorted(by: { $0.key < $1.key }) {
            continuation.yield(
              .toolCall(
                ToolCall(
                  id: tc.id,
                  type: "function",
                  function: .init(name: tc.name, arguments: tc.arguments)
                )))
          }

          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private var defaultBytesLoader: BytesLoader {
    { request in
      try await URLSession.shared.bytes(for: request)
    }
  }
}

struct OpenAIStreamingChunk: Decodable {
  let choices: [Choice]

  struct Choice: Decodable {
    let delta: Delta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
      case delta
      case finishReason = "finish_reason"
    }
  }

  struct Delta: Decodable {
    let content: String?
    let toolCalls: [ToolCallDelta]?

    enum CodingKeys: String, CodingKey {
      case content
      case toolCalls = "tool_calls"
    }
  }

  struct ToolCallDelta: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: FunctionDelta?

    struct FunctionDelta: Decodable {
      let name: String?
      let arguments: String?
    }
  }
}
