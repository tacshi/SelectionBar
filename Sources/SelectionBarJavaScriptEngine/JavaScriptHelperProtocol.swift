import Foundation

/// Wire format between SelectionBar and the out-of-process JavaScript helper.
///
/// One request per process: the parent writes a request as JSON to the helper's
/// stdin, the helper writes a single response as JSON to stdout and exits. That
/// keeps the helper stateless and lets the parent kill it at any moment without
/// leaving anything to clean up.
public struct JavaScriptHelperRequest: Codable, Sendable {
  public var script: String
  public var input: String
  public var syncTimeoutMilliseconds: Int
  public var asyncTimeoutMilliseconds: Int

  public init(
    script: String,
    input: String,
    syncTimeoutMilliseconds: Int,
    asyncTimeoutMilliseconds: Int
  ) {
    self.script = script
    self.input = input
    self.syncTimeoutMilliseconds = syncTimeoutMilliseconds
    self.asyncTimeoutMilliseconds = asyncTimeoutMilliseconds
  }
}

/// The error cases the helper can report, mapped back to
/// `SelectionBarJavaScriptRunnerError` in the parent so callers see the same
/// errors whether the script ran in-process or out-of-process.
public enum JavaScriptHelperErrorKind: String, Codable, Sendable {
  case missingScript
  case syntaxError
  case missingTransform
  case invalidReturnType
  case runtimeError
  case timeout
}

public struct JavaScriptHelperResponse: Codable, Sendable {
  public var value: String?
  public var errorKind: JavaScriptHelperErrorKind?
  public var message: String?

  public init(
    value: String? = nil,
    errorKind: JavaScriptHelperErrorKind? = nil,
    message: String? = nil
  ) {
    self.value = value
    self.errorKind = errorKind
    self.message = message
  }

  public static func success(_ value: String) -> JavaScriptHelperResponse {
    JavaScriptHelperResponse(value: value)
  }

  public static func failure(_ error: SelectionBarJavaScriptRunnerError)
    -> JavaScriptHelperResponse
  {
    switch error {
    case .missingScript:
      return JavaScriptHelperResponse(errorKind: .missingScript)
    case .syntaxError(let message):
      return JavaScriptHelperResponse(errorKind: .syntaxError, message: message)
    case .missingTransform:
      return JavaScriptHelperResponse(errorKind: .missingTransform)
    case .invalidReturnType:
      return JavaScriptHelperResponse(errorKind: .invalidReturnType)
    case .runtimeError(let message):
      return JavaScriptHelperResponse(errorKind: .runtimeError, message: message)
    case .timeout:
      return JavaScriptHelperResponse(errorKind: .timeout)
    }
  }

  /// Reconstructs the original error, or returns the value on success.
  public func resolve() throws -> String {
    if let errorKind {
      throw errorKind.error(message: message)
    }
    guard let value else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "JavaScript helper returned no result.")
    }
    return value
  }
}

extension JavaScriptHelperErrorKind {
  public func error(message: String?) -> SelectionBarJavaScriptRunnerError {
    switch self {
    case .missingScript:
      return .missingScript
    case .syntaxError:
      return .syntaxError(message ?? "")
    case .missingTransform:
      return .missingTransform
    case .invalidReturnType:
      return .invalidReturnType
    case .runtimeError:
      return .runtimeError(message ?? "")
    case .timeout:
      return .timeout
    }
  }
}
