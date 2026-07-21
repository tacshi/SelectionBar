import Foundation
import SelectionBarJavaScriptEngine

// A one-shot JavaScript sandbox. SelectionBar spawns this helper, writes a
// request to stdin and reads a response from stdout. Because the script runs
// here rather than in the app, a runaway `while (true) {}` costs a killable
// child process instead of a permanently pinned core inside SelectionBar.

func emit(_ response: JavaScriptHelperResponse) -> Never {
  let encoder = JSONEncoder()
  if let data = try? encoder.encode(response) {
    FileHandle.standardOutput.write(data)
  }
  exit(0)
}

let requestData = FileHandle.standardInput.readDataToEndOfFile()

guard
  let request = try? JSONDecoder().decode(JavaScriptHelperRequest.self, from: requestData)
else {
  emit(
    JavaScriptHelperResponse(
      errorKind: .runtimeError,
      message: "JavaScript helper received a malformed request."
    ))
}

let runner = SelectionBarJavaScriptRunner(
  defaultTimeout: .milliseconds(request.syncTimeoutMilliseconds),
  defaultAsyncTimeout: .milliseconds(request.asyncTimeoutMilliseconds)
)

// The parent enforces the real wall-clock deadline and kills this process if it
// is exceeded, so there is no need to race a timer here.
let semaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) var outcome = JavaScriptHelperResponse(
  errorKind: .runtimeError,
  message: "JavaScript helper produced no result."
)

// `Task.detached`, not `Task`: top-level code in main.swift is main-actor
// isolated, so an inherited-context task could never start while the main
// thread is parked on the semaphore below.
Task.detached {
  do {
    let value = try await runner.run(script: request.script, input: request.input)
    outcome = .success(value)
  } catch let error as SelectionBarJavaScriptRunnerError {
    outcome = .failure(error)
  } catch {
    outcome = JavaScriptHelperResponse(
      errorKind: .runtimeError,
      message: error.localizedDescription
    )
  }
  semaphore.signal()
}

semaphore.wait()
emit(outcome)
