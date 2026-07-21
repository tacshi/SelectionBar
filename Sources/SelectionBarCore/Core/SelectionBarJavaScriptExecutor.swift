import Foundation
import SelectionBarJavaScriptEngine
import os.log

private let logger = Logger(
  subsystem: "com.selectionbar",
  category: "SelectionBarJavaScriptExecutor"
)

/// Runs a JavaScript action, preferring a separate helper process.
///
/// JavaScriptCore gives no supported way to interrupt a script from Swift — the
/// runner's timeout only stops *waiting*, so a `while (true) {}` in a user
/// script would otherwise keep a core pinned for the lifetime of the app, once
/// per invocation. Running in a child process makes the timeout enforceable:
/// the deadline is a kill, not a give-up.
///
/// When the helper cannot be found (unit tests, or a `swift build` product tree
/// rather than an app bundle) execution falls back to the in-process engine,
/// which behaves identically apart from being uninterruptible.
public struct SelectionBarJavaScriptExecutor: Sendable {
  /// Name of the bundled helper executable.
  static let helperExecutableName = "selectionbar-js-helper"

  /// Grace period beyond the script's own async timeout before the helper is
  /// killed. The helper should finish on its own well inside this.
  static let terminationGrace = Duration.seconds(2)

  /// How long to wait for a SIGTERM to be honoured before escalating to
  /// SIGKILL. A spinning script never reaches a signal handler, so this stays
  /// short.
  static let sigkillEscalation = Duration.milliseconds(250)

  private let syncTimeout: Duration
  private let asyncTimeout: Duration
  private let helperURLProvider: @Sendable () -> URL?

  public init(
    syncTimeout: Duration = .milliseconds(800),
    asyncTimeout: Duration = .seconds(10)
  ) {
    self.init(
      syncTimeout: syncTimeout,
      asyncTimeout: asyncTimeout,
      helperURLProvider: { Self.bundledHelperURL() }
    )
  }

  init(
    syncTimeout: Duration,
    asyncTimeout: Duration,
    helperURLProvider: @escaping @Sendable () -> URL?
  ) {
    self.syncTimeout = syncTimeout
    self.asyncTimeout = asyncTimeout
    self.helperURLProvider = helperURLProvider
  }

  public func run(script: String, input: String) async throws -> String {
    guard let helperURL = helperURLProvider() else {
      logger.debug("JavaScript helper unavailable — running in-process")
      return try await runInProcess(script: script, input: input)
    }

    do {
      return try await runInHelper(helperURL: helperURL, script: script, input: input)
    } catch let error as SelectionBarHelperLaunchError {
      // The helper never started, so the script has definitely not run yet and
      // retrying in-process cannot duplicate any side effects.
      logger.error(
        "JavaScript helper failed to launch (\(error.underlyingDescription, privacy: .private)) — running in-process"
      )
      return try await runInProcess(script: script, input: input)
    }
    // Every other failure — a script error, a timeout, a crashed helper, or
    // unreadable output — happens once the helper is already running. The
    // script may have completed a side-effectful `fetch` by then, so it must
    // never be re-run. Surface the failure instead.
  }

  private func runInProcess(script: String, input: String) async throws -> String {
    try await SelectionBarJavaScriptRunner(
      defaultTimeout: syncTimeout,
      defaultAsyncTimeout: asyncTimeout
    ).run(script: script, input: input)
  }

  private func runInHelper(
    helperURL: URL,
    script: String,
    input: String
  ) async throws -> String {
    let request = JavaScriptHelperRequest(
      script: script,
      input: input,
      syncTimeoutMilliseconds: syncTimeout.wholeMilliseconds,
      asyncTimeoutMilliseconds: asyncTimeout.wholeMilliseconds
    )
    guard let requestData = try? JSONEncoder().encode(request) else {
      throw SelectionBarHelperLaunchError.launchFailed(
        SelectionBarJavaScriptRunnerError.runtimeError("Could not encode the helper request."))
    }
    let deadline = asyncTimeout + Self.terminationGrace

    let process = Process()
    process.executableURL = helperURL
    let stdinPipe = Pipe()
    let stdoutPipe = Pipe()
    process.standardInput = stdinPipe
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      throw SelectionBarHelperLaunchError.launchFailed(error)
    }

    // Read on a background queue: the helper cannot exit until it has written
    // its response, and it cannot write if the pipe buffer is full and nobody
    // is draining it.
    let output = OutputCollector()
    let readQueue = DispatchQueue(label: "selectionbar.javascript.helper.read")
    readQueue.async {
      output.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
    }

    stdinPipe.fileHandleForWriting.write(requestData)
    try? stdinPipe.fileHandleForWriting.close()

    let exited = await withTaskCancellationHandler {
      await Self.wait(for: process, upTo: deadline)
    } onCancel: {
      Self.kill(process)
    }

    guard exited else {
      logger.error("JavaScript helper exceeded its deadline — terminating")
      Self.kill(process)
      throw SelectionBarJavaScriptRunnerError.timeout
    }

    try Task.checkCancellation()

    // Past this point the helper has run, so failures are reported rather than
    // retried — see `run(script:input:)`.
    let data = output.waitForValue()
    guard !data.isEmpty else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "The JavaScript helper exited without returning a result.")
    }
    guard let response = try? JSONDecoder().decode(JavaScriptHelperResponse.self, from: data) else {
      throw SelectionBarJavaScriptRunnerError.runtimeError(
        "The JavaScript helper returned malformed output.")
    }
    return try response.resolve()
  }

  /// Polls rather than blocking a thread in `waitUntilExit()`, so no cooperative
  /// pool thread is held while a script runs.
  private static func wait(for process: Process, upTo deadline: Duration) async -> Bool {
    let pollInterval = Duration.milliseconds(20)
    var waited = Duration.zero
    while process.isRunning {
      if waited >= deadline { return false }
      do {
        try await Task.sleep(for: pollInterval)
      } catch {
        return !process.isRunning
      }
      waited += pollInterval
    }
    return true
  }

  private static func kill(_ process: Process) {
    guard process.isRunning else { return }
    process.terminate()
    // A script spinning inside JavaScriptCore never returns to a point where a
    // signal handler can run, so SIGTERM alone is not enough.
    let pid = process.processIdentifier
    DispatchQueue.global(qos: .utility)
      .asyncAfter(deadline: .now() + sigkillEscalation.timeIntervalValue) {
        if process.isRunning {
          Darwin.kill(pid, SIGKILL)
        }
      }
  }

  /// Looks for the helper next to the running executable, then in the app
  /// bundle's `Contents/Helpers`.
  static func bundledHelperURL() -> URL? {
    var candidates: [URL] = []

    let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
      .resolvingSymlinksInPath()
    let executableDirectory = executableURL.deletingLastPathComponent()
    candidates.append(executableDirectory.appendingPathComponent(helperExecutableName))
    candidates.append(
      executableDirectory
        .deletingLastPathComponent()
        .appendingPathComponent("Helpers", isDirectory: true)
        .appendingPathComponent(helperExecutableName)
    )

    if let bundleHelpers = Bundle.main.sharedSupportURL {
      candidates.append(bundleHelpers.appendingPathComponent(helperExecutableName))
    }

    for candidate in candidates
    where FileManager.default.isExecutableFile(atPath: candidate.path) {
      return candidate
    }
    return nil
  }
}

/// Raised only when the helper process could not be started at all. Anything
/// that happens after `run()` succeeds is reported to the caller instead, since
/// the script may already have run.
enum SelectionBarHelperLaunchError: Error {
  case launchFailed(any Error)

  var underlyingDescription: String {
    switch self {
    case .launchFailed(let error):
      return error.localizedDescription
    }
  }
}

/// Carries the helper's stdout from the reader queue back to the caller.
private final class OutputCollector: @unchecked Sendable {
  private let lock = NSLock()
  private let ready = DispatchSemaphore(value: 0)
  private var value = Data()

  func set(_ data: Data) {
    lock.lock()
    value = data
    lock.unlock()
    ready.signal()
  }

  func waitForValue() -> Data {
    ready.wait()
    lock.lock()
    defer { lock.unlock() }
    return value
  }
}

extension Duration {
  fileprivate var wholeMilliseconds: Int {
    let (seconds, attoseconds) = components
    return Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000)
  }

  fileprivate var timeIntervalValue: TimeInterval {
    let (seconds, attoseconds) = components
    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
  }
}
