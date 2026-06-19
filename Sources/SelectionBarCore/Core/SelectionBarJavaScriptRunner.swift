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
  public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  public let defaultTimeout: Duration
  public let defaultAsyncTimeout: Duration

  private let dataLoader: DataLoader

  public init(
    defaultTimeout: Duration = .milliseconds(800),
    defaultAsyncTimeout: Duration = .seconds(10),
    dataLoader: @escaping DataLoader = { request in
      try await URLSession.shared.data(for: request)
    }
  ) {
    self.defaultTimeout = defaultTimeout
    self.defaultAsyncTimeout = defaultAsyncTimeout
    self.dataLoader = dataLoader
  }

  public func run(
    script: String,
    input: String,
    timeout: Duration? = nil,
    asyncTimeout: Duration? = nil
  ) async throws -> String {
    let resolvedTimeout = timeout ?? defaultTimeout
    let resolvedAsyncTimeout = asyncTimeout ?? defaultAsyncTimeout
    let trimmedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedScript.isEmpty else {
      throw SelectionBarJavaScriptRunnerError.missingScript
    }

    let executionState = JavaScriptExecutionState()
    let task = Task.detached(priority: .userInitiated) {
      try Self.execute(
        script: trimmedScript,
        input: input,
        syncTimeout: resolvedTimeout,
        asyncTimeout: resolvedAsyncTimeout,
        dataLoader: dataLoader,
        state: executionState
      )
    }

    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      executionState.cancel()
      task.cancel()
    }
  }

  private static func execute(
    script: String,
    input: String,
    syncTimeout: Duration,
    asyncTimeout: Duration,
    dataLoader: @escaping DataLoader,
    state: JavaScriptExecutionState
  ) throws -> String {
    let environment = JavaScriptExecutionEnvironment(
      state: state,
      dataLoader: dataLoader,
      requestTimeout: asyncTimeout
    )

    environment.start(script: script, input: input)

    guard state.waitForInitial(timeout: syncTimeout) else {
      state.cancel()
      throw SelectionBarJavaScriptRunnerError.timeout
    }
    if state.isCancelledSnapshot {
      throw CancellationError()
    }
    try Task.checkCancellation()

    if let result = state.result {
      return try result.get()
    }

    guard state.waitForFinal(timeout: asyncTimeout) else {
      state.cancel()
      throw SelectionBarJavaScriptRunnerError.timeout
    }
    if state.isCancelledSnapshot {
      throw CancellationError()
    }
    try Task.checkCancellation()

    guard let result = state.result else {
      throw SelectionBarJavaScriptRunnerError.runtimeError("JavaScript execution failed.")
    }
    return try result.get()
  }
}

private final class JavaScriptExecutionState: @unchecked Sendable {
  private let lock = NSLock()
  private let initialSemaphore = DispatchSemaphore(value: 0)
  private let finalSemaphore = DispatchSemaphore(value: 0)

  private var isInitialComplete = false
  private var isCancelled = false
  private var storedResult: Result<String, SelectionBarJavaScriptRunnerError>?
  private var exceptionMessage: String?
  private var fetchTasks: [Task<Void, Never>] = []

  var result: Result<String, SelectionBarJavaScriptRunnerError>? {
    lock.lock()
    defer { lock.unlock() }
    return storedResult
  }

  func setException(_ message: String) {
    lock.lock()
    exceptionMessage = message
    lock.unlock()
  }

  func clearException() {
    lock.lock()
    exceptionMessage = nil
    lock.unlock()
  }

  func consumeException() -> String? {
    lock.lock()
    defer { lock.unlock() }
    let message = exceptionMessage
    exceptionMessage = nil
    return message
  }

  func markWaitingForPromise() {
    completeInitialIfNeeded()
  }

  func complete(_ result: Result<String, SelectionBarJavaScriptRunnerError>) {
    lock.lock()
    guard storedResult == nil, !isCancelled else {
      lock.unlock()
      return
    }

    storedResult = result
    let shouldSignalInitial = !isInitialComplete
    if shouldSignalInitial {
      isInitialComplete = true
    }
    lock.unlock()

    if shouldSignalInitial {
      initialSemaphore.signal()
    }
    finalSemaphore.signal()
  }

  func waitForInitial(timeout: Duration) -> Bool {
    if isInitialCompleteSnapshot { return true }
    return initialSemaphore.wait(timeout: .now() + timeout.dispatchInterval) == .success
  }

  func waitForFinal(timeout: Duration) -> Bool {
    if result != nil { return true }
    return finalSemaphore.wait(timeout: .now() + timeout.dispatchInterval) == .success
  }

  func registerFetchTask(_ task: Task<Void, Never>) {
    lock.lock()
    if isCancelled {
      lock.unlock()
      task.cancel()
      return
    }
    fetchTasks.append(task)
    lock.unlock()
  }

  func cancel() {
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    isCancelled = true
    let shouldSignalInitial = !isInitialComplete
    if shouldSignalInitial {
      isInitialComplete = true
    }
    let shouldSignalFinal = storedResult == nil
    let tasks = fetchTasks
    fetchTasks.removeAll()
    lock.unlock()

    if shouldSignalInitial {
      initialSemaphore.signal()
    }
    if shouldSignalFinal {
      finalSemaphore.signal()
    }
    for task in tasks {
      task.cancel()
    }
  }

  var isCancelledSnapshot: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isCancelled
  }

  private var isInitialCompleteSnapshot: Bool {
    lock.lock()
    defer { lock.unlock() }
    return isInitialComplete
  }

  private func completeInitialIfNeeded() {
    lock.lock()
    guard !isInitialComplete else {
      lock.unlock()
      return
    }
    isInitialComplete = true
    lock.unlock()
    initialSemaphore.signal()
  }
}

private final class JavaScriptExecutionEnvironment: @unchecked Sendable {
  private let queue = DispatchQueue(label: "selectionbar.javascript.runner")
  private let state: JavaScriptExecutionState
  private let dataLoader: SelectionBarJavaScriptRunner.DataLoader
  private let requestTimeout: Duration

  private var context: JSContext?
  private var retainedObjects: [AnyObject] = []

  init(
    state: JavaScriptExecutionState,
    dataLoader: @escaping SelectionBarJavaScriptRunner.DataLoader,
    requestTimeout: Duration
  ) {
    self.state = state
    self.dataLoader = dataLoader
    self.requestTimeout = requestTimeout
  }

  func start(script: String, input: String) {
    queue.async { [self] in
      execute(script: script, input: input)
    }
  }

  private func execute(script: String, input: String) {
    let virtualMachine = JSVirtualMachine()
    let context = JSContext(virtualMachine: virtualMachine)
    guard let context else {
      state.complete(
        .failure(
          .runtimeError("Failed to initialize JavaScript context.")
        )
      )
      return
    }

    self.context = context
    context.exceptionHandler = { _, exception in
      self.state.setException(exception?.toString() ?? "Unknown JavaScript exception.")
    }
    installFetch(in: context)

    let sourceURL = URL(string: "selectionbar://script-action.js")
    state.clearException()
    _ = context.evaluateScript(script, withSourceURL: sourceURL)
    if let exceptionMessage = state.consumeException() {
      state.complete(.failure(.syntaxError(exceptionMessage)))
      return
    }

    let isTransformFunction =
      context.evaluateScript("typeof transform === 'function'")?.toBool() ?? false
    guard isTransformFunction else {
      state.complete(.failure(.missingTransform))
      return
    }

    guard let transform = context.objectForKeyedSubscript("transform") else {
      state.complete(.failure(.missingTransform))
      return
    }

    state.clearException()
    let resultValue = transform.call(withArguments: [input])
    if let exceptionMessage = state.consumeException() {
      state.complete(.failure(.runtimeError(exceptionMessage)))
      return
    }
    guard let resultValue else {
      state.complete(.failure(.runtimeError("transform(input) did not return a value.")))
      return
    }

    if resultValue.isString {
      state.complete(.success(resultValue.toString() ?? ""))
      return
    }

    if isThenable(resultValue, in: context) {
      observePromise(resultValue, in: context)
      return
    }

    state.complete(.failure(.invalidReturnType))
  }

  private func installFetch(in context: JSContext) {
    let fetchBlock: @convention(block) (JSValue, JSValue) -> JSValue = {
      [weak self, weak context] urlValue, initValue in
      guard let context = JSContext.current() ?? context else {
        return JSValue()
      }
      guard let self else {
        return JSValue(undefinedIn: context)
      }

      guard let promiseConstructor = context.objectForKeyedSubscript("Promise") else {
        return JSValue(undefinedIn: context)
      }

      let executor: @convention(block) (JSValue, JSValue) -> Void = { resolve, reject in
        self.startFetch(
          urlValue: urlValue,
          initValue: initValue,
          context: context,
          resolve: resolve,
          reject: reject
        )
      }
      let executorObject = unsafeBitCast(executor, to: AnyObject.self)
      self.retain(executorObject)

      return promiseConstructor.construct(withArguments: [executorObject])
        ?? JSValue(undefinedIn: context)
    }
    let fetchObject = unsafeBitCast(fetchBlock, to: AnyObject.self)
    retain(fetchObject)
    context.setObject(fetchObject, forKeyedSubscript: "fetch" as NSString)
  }

  private func startFetch(
    urlValue: JSValue,
    initValue: JSValue,
    context: JSContext,
    resolve: JSValue,
    reject: JSValue
  ) {
    let pendingFetch = JavaScriptPendingFetch(resolve: resolve, reject: reject)

    let request: URLRequest
    do {
      request = try makeRequest(urlValue: urlValue, initValue: initValue)
    } catch let error as SelectionBarJavaScriptRunnerError {
      rejectFetch(pendingFetch, message: error.fetchRejectionMessage)
      return
    } catch {
      rejectFetch(pendingFetch, message: error.localizedDescription)
      return
    }

    let dataLoader = dataLoader
    let task = Task {
      do {
        let (data, response) = try await dataLoader(request)
        guard !Task.isCancelled else { return }

        queue.async { [self] in
          guard let context = self.context, !state.isCancelledSnapshot else { return }
          guard let httpResponse = response as? HTTPURLResponse else {
            rejectFetch(pendingFetch, message: "fetch received an invalid response.")
            return
          }

          let responseValue = makeResponseValue(
            data: data,
            response: httpResponse,
            requestURL: request.url,
            context: context
          )
          pendingFetch.resolve.call(withArguments: [responseValue as Any])
        }
      } catch {
        guard !Task.isCancelled, !state.isCancelledSnapshot else { return }
        queue.async { [self] in
          guard !state.isCancelledSnapshot else { return }
          rejectFetch(pendingFetch, message: error.localizedDescription)
        }
      }
    }
    state.registerFetchTask(task)
  }

  private func makeRequest(urlValue: JSValue, initValue: JSValue) throws -> URLRequest {
    guard let urlString = urlValue.toString(),
      let url = URL(string: urlString),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https"
    else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "fetch supports only http and https URLs.")
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = requestTimeout.timeInterval

    guard !initValue.isUndefined, !initValue.isNull else {
      request.httpMethod = "GET"
      return request
    }
    guard initValue.isObject else {
      throw SelectionBarJavaScriptRunnerError.runtimeError("fetch init must be an object.")
    }

    if let methodValue = initValue.objectForKeyedSubscript("method"),
      !methodValue.isUndefined,
      !methodValue.isNull
    {
      request.httpMethod = methodValue.toString()?.uppercased() ?? "GET"
    } else {
      request.httpMethod = "GET"
    }

    if let headersValue = initValue.objectForKeyedSubscript("headers"),
      !headersValue.isUndefined,
      !headersValue.isNull
    {
      guard headersValue.isObject, let headers = headersValue.toDictionary() else {
        throw SelectionBarJavaScriptRunnerError.runtimeError(
          "fetch headers must be a plain object.")
      }
      for (key, value) in headers {
        request.setValue(String(describing: value), forHTTPHeaderField: String(describing: key))
      }
    }

    if let bodyValue = initValue.objectForKeyedSubscript("body"),
      !bodyValue.isUndefined,
      !bodyValue.isNull
    {
      guard bodyValue.isString, let body = bodyValue.toString() else {
        throw SelectionBarJavaScriptRunnerError.runtimeError("fetch body must be a string.")
      }
      request.httpBody = Data(body.utf8)
    }

    return request
  }

  private func makeResponseValue(
    data: Data,
    response: HTTPURLResponse,
    requestURL: URL?,
    context: JSContext
  ) -> JSValue {
    let bodyText = String(decoding: data, as: UTF8.self)
    let headersValue = JSValue(newObjectIn: context)

    for (key, value) in response.allHeaderFields {
      headersValue?.setValue(String(describing: value), forProperty: String(describing: key))
    }

    let factory = context.evaluateScript(
      """
      (function(status, statusText, url, headers, bodyText) {
        return {
          ok: status >= 200 && status <= 299,
          status: status,
          statusText: statusText,
          url: url,
          headers: headers,
          text: function() {
            return Promise.resolve(bodyText);
          },
          json: function() {
            try {
              return Promise.resolve(JSON.parse(bodyText));
            } catch (error) {
              return Promise.reject(error);
            }
          }
        };
      })
      """
    )

    return factory?.call(withArguments: [
      response.statusCode,
      HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
      requestURL?.absoluteString ?? response.url?.absoluteString ?? "",
      headersValue as Any,
      bodyText,
    ]) ?? JSValue(undefinedIn: context)
  }

  private func isThenable(_ value: JSValue, in context: JSContext) -> Bool {
    let checker = context.evaluateScript(
      "(function(value) { return value && typeof value.then === 'function'; })")
    return checker?.call(withArguments: [value])?.toBool() ?? false
  }

  private func observePromise(_ promise: JSValue, in context: JSContext) {
    let onFulfilled: @convention(block) (JSValue) -> Void = { [weak self] value in
      guard let self else { return }
      if value.isString {
        self.state.complete(.success(value.toString() ?? ""))
      } else {
        self.state.complete(.failure(.invalidReturnType))
      }
    }

    let onRejected: @convention(block) (JSValue) -> Void = { [weak self] reason in
      self?.state.complete(
        .failure(.runtimeError(reason.toString() ?? "Promise rejected."))
      )
    }

    let fulfilledObject = unsafeBitCast(onFulfilled, to: AnyObject.self)
    let rejectedObject = unsafeBitCast(onRejected, to: AnyObject.self)
    retain(fulfilledObject)
    retain(rejectedObject)

    state.clearException()
    _ = promise.invokeMethod("then", withArguments: [fulfilledObject, rejectedObject])
    if let exceptionMessage = state.consumeException() {
      state.complete(.failure(.runtimeError(exceptionMessage)))
      return
    }

    state.markWaitingForPromise()
  }

  private func rejectFetch(_ pendingFetch: JavaScriptPendingFetch, message: String) {
    pendingFetch.reject.call(withArguments: [message])
  }

  private func retain(_ object: AnyObject) {
    retainedObjects.append(object)
  }
}

private final class JavaScriptPendingFetch: @unchecked Sendable {
  let resolve: JSValue
  let reject: JSValue

  init(resolve: JSValue, reject: JSValue) {
    self.resolve = resolve
    self.reject = reject
  }
}

extension Duration {
  fileprivate var dispatchInterval: DispatchTimeInterval {
    .nanoseconds(Int(clamping: nanoseconds))
  }

  fileprivate var timeInterval: TimeInterval {
    TimeInterval(nanoseconds) / 1_000_000_000
  }

  private var nanoseconds: Int64 {
    let components = components
    let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
    let attosecondNanoseconds = components.attoseconds / 1_000_000_000

    if seconds.overflow {
      return components.seconds >= 0 ? Int64.max : Int64.min
    }

    let total = seconds.partialValue.addingReportingOverflow(attosecondNanoseconds)
    if total.overflow {
      return seconds.partialValue >= 0 ? Int64.max : Int64.min
    }
    return max(0, total.partialValue)
  }
}

extension SelectionBarJavaScriptRunnerError {
  fileprivate var fetchRejectionMessage: String {
    switch self {
    case .runtimeError(let message), .syntaxError(let message):
      return message
    case .missingScript, .missingTransform, .invalidReturnType, .timeout:
      return localizedDescription
    }
  }
}
