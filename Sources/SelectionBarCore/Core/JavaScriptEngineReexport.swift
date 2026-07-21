// The JavaScript engine lives in its own target so the out-of-process helper
// can link it too. Re-export it so callers (and tests) importing SelectionBarCore
// keep seeing `SelectionBarJavaScriptRunner` and its error type unchanged.
@_exported import SelectionBarJavaScriptEngine
