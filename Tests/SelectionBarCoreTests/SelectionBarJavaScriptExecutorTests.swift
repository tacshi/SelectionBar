import Foundation
import Testing

@testable import SelectionBarCore
@testable import SelectionBarJavaScriptEngine

@Suite("SelectionBarJavaScriptExecutor Tests")
struct SelectionBarJavaScriptExecutorTests {
  /// Writes an executable shell script to a temp dir and returns its URL.
  private func makeFakeHelper(body: String) throws -> (url: URL, cleanup: () -> Void) {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("SelectionBarHelperTests.\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fake-helper")
    try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: url.path)
    return (url, { try? FileManager.default.removeItem(at: directory) })
  }

  @Test("falls back to the in-process engine when no helper is bundled")
  func fallsBackWhenHelperMissing() async throws {
    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(800),
      asyncTimeout: .seconds(1),
      helperURLProvider: { nil }
    )

    let output = try await executor.run(
      script: "function transform(input) { return input.toUpperCase(); }",
      input: "fallback"
    )

    #expect(output == "FALLBACK")
  }

  @Test("falls back when the helper cannot be launched")
  func fallsBackWhenHelperUnlaunchable() async throws {
    let missing = URL(fileURLWithPath: "/nonexistent/selectionbar-js-helper")
    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(800),
      asyncTimeout: .seconds(1),
      helperURLProvider: { missing }
    )

    let output = try await executor.run(
      script: "function transform(input) { return input + '!'; }",
      input: "still works"
    )

    #expect(output == "still works!")
  }

  @Test("returns the helper's successful response")
  func returnsHelperSuccess() async throws {
    let helper = try makeFakeHelper(body: #"cat > /dev/null; printf '{"value":"FROM HELPER"}'"#)
    defer { helper.cleanup() }
    let helperURL = helper.url

    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(800),
      asyncTimeout: .seconds(1),
      helperURLProvider: { helperURL }
    )

    let output = try await executor.run(script: "irrelevant", input: "irrelevant")
    #expect(output == "FROM HELPER")
  }

  @Test("maps a helper error response back to the runner error")
  func mapsHelperError() async throws {
    let helper = try makeFakeHelper(
      body: #"cat > /dev/null; printf '{"errorKind":"missingTransform"}'"#)
    defer { helper.cleanup() }
    let helperURL = helper.url

    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(800),
      asyncTimeout: .seconds(1),
      helperURLProvider: { helperURL }
    )

    await #expect(throws: SelectionBarJavaScriptRunnerError.missingTransform) {
      try await executor.run(script: "irrelevant", input: "irrelevant")
    }
  }

  @Test("a script error from the helper is not retried in-process")
  func scriptErrorIsNotRetried() async throws {
    // The helper reports a syntax error; the executor must surface it rather
    // than re-running the script locally (a rerun could repeat fetch side
    // effects).
    let helper = try makeFakeHelper(
      body: #"cat > /dev/null; printf '{"errorKind":"syntaxError","message":"boom"}'"#)
    defer { helper.cleanup() }
    let helperURL = helper.url

    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(800),
      asyncTimeout: .seconds(1),
      helperURLProvider: { helperURL }
    )

    await #expect(throws: SelectionBarJavaScriptRunnerError.syntaxError("boom")) {
      // A valid script — if this were retried in-process it would succeed.
      try await executor.run(
        script: "function transform(input) { return input; }",
        input: "x"
      )
    }
  }

  @Test("kills a helper that blows through its deadline")
  func killsHelperPastDeadline() async throws {
    let helper = try makeFakeHelper(body: "cat > /dev/null; sleep 120")
    defer { helper.cleanup() }
    let helperURL = helper.url

    let executor = SelectionBarJavaScriptExecutor(
      syncTimeout: .milliseconds(50),
      asyncTimeout: .milliseconds(100),
      helperURLProvider: { helperURL }
    )

    let started = ContinuousClock.now
    await #expect(throws: SelectionBarJavaScriptRunnerError.timeout) {
      try await executor.run(script: "irrelevant", input: "irrelevant")
    }
    let elapsed = ContinuousClock.now - started

    // Deadline is asyncTimeout + terminationGrace; it must not wait out sleep 120.
    #expect(elapsed < .seconds(15))
  }
}
