import Foundation
import JavaScriptCore

public enum SelectionBarJavaScriptRunnerError: Error, LocalizedError, Equatable {
  case missingScript
  case syntaxError(String)
  case missingTransform
  case invalidReturnType
  case runtimeError(String)
  case timeout

  public var errorDescription: String? {
    switch self {
    case .missingScript:
      return "JavaScript action script is empty."
    case .syntaxError(let message):
      return "JavaScript syntax error: \(message)"
    case .missingTransform:
      return "JavaScript action must define a function named transform(input)."
    case .invalidReturnType:
      return "JavaScript action transform(input) must return a string."
    case .runtimeError(let message):
      return "JavaScript runtime error: \(message)"
    case .timeout:
      return "JavaScript action timed out."
    }
  }
}

public struct SelectionBarJavaScriptRunner: Sendable {
  public let defaultTimeout: Duration

  public init(defaultTimeout: Duration = .milliseconds(800)) {
    self.defaultTimeout = defaultTimeout
  }

  public func run(script: String, input: String, timeout: Duration? = nil) async throws -> String {
    let resolvedTimeout = timeout ?? defaultTimeout
    let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedScript.isEmpty else {
      throw SelectionBarJavaScriptRunnerError.missingScript
    }

    return try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask {
        try Self.executeSynchronously(script: trimmedScript, input: input)
      }
      group.addTask {
        try await Task.sleep(for: resolvedTimeout)
        throw SelectionBarJavaScriptRunnerError.timeout
      }

      guard let firstResult = try await group.next() else {
        throw SelectionBarJavaScriptRunnerError.runtimeError("JavaScript execution failed.")
      }
      group.cancelAll()
      return firstResult
    }
  }

  private static func executeSynchronously(script: String, input: String) throws -> String {
    let virtualMachine = JSVirtualMachine()
    let context = JSContext(virtualMachine: virtualMachine)
    guard let context else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "Failed to initialize JavaScript context.")
    }

    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
      exceptionMessage = exception?.toString() ?? "Unknown JavaScript exception."
    }

    let sourceURL = URL(string: "selectionbar://script-action.js")
    _ = context.evaluateScript(script, withSourceURL: sourceURL)
    if let exceptionMessage {
      throw SelectionBarJavaScriptRunnerError.syntaxError(exceptionMessage)
    }

    let isTransformFunction =
      context.evaluateScript("typeof transform === 'function'")?.toBool() ?? false
    guard isTransformFunction else {
      throw SelectionBarJavaScriptRunnerError.missingTransform
    }

    guard let transform = context.objectForKeyedSubscript("transform") else {
      throw SelectionBarJavaScriptRunnerError.missingTransform
    }

    let resultValue = transform.call(withArguments: [input])
    if let exceptionMessage {
      throw SelectionBarJavaScriptRunnerError.runtimeError(exceptionMessage)
    }
    guard let resultValue else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "transform(input) did not return a value.")
    }
    guard resultValue.isString else {
      throw SelectionBarJavaScriptRunnerError.invalidReturnType
    }
    return resultValue.toString() ?? ""
  }
}
