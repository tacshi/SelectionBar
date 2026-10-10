import AppKit
@preconcurrency import ApplicationServices
import Carbon.HIToolbox

@MainActor
protocol GrammarTextAccessing: AnyObject {
  func capture(preferSelection: Bool) throws -> GrammarTextSnapshot
  func captureClipboardSelection() async throws -> GrammarTextSnapshot
  func isCurrent(_ snapshot: GrammarTextSnapshot, checkSelection: Bool) -> Bool
  func sourceStatus(_ snapshot: GrammarTextSnapshot, allowPanelFocus: Bool) -> GrammarSourceStatus
  func prepareSource(_ snapshot: GrammarTextSnapshot, requireUnchanged: Bool) async throws
  func apply(_ suggestion: GrammarSuggestion, to snapshot: GrammarTextSnapshot) async throws
    -> GrammarTextSnapshot
  func underlineLayout(for suggestions: [GrammarSuggestion], in snapshot: GrammarTextSnapshot)
    -> GrammarUnderlineLayout?
}

@MainActor
final class GrammarTextAccess: GrammarTextAccessing {
  private var target: AXUIElement?
  private var targetWindow: AXUIElement?
  private var targetID = UUID()
  private let clipboard = SelectionBarClipboardService()

  func capture(preferSelection: Bool) throws -> GrammarTextSnapshot {
    let (app, focused) = try Self.focusedContext()
    let candidates = Self.ancestors(of: focused)
    guard !candidates.contains(where: Self.isSecure) else { throw GrammarCheckError.unavailable }
    guard !candidates.contains(where: Self.isComposing) else { throw GrammarCheckError.composition }

    let sources = candidates.map { element in
      let value = Self.value(element)
      let selection = Self.range(element, kAXSelectedTextRangeAttribute)
      let editable = value != nil && selection != nil && Self.isEditable(element)
      return GrammarAccessibleText(
        fullText: value,
        selectedRange: selection,
        selectedText: preferSelection ? Self.string(element, kAXSelectedTextAttribute) : nil,
        isEditable: editable,
        canSelectRange: editable && Self.isSettable(element, kAXSelectedTextRangeAttribute)
      )
    }
    let captured = try GrammarTextCapture.resolve(sources, preferSelection: preferSelection)
    return snapshot(
      app: app, element: candidates[captured.sourceIndex], value: captured.fullText,
      range: captured.checkedRange, selection: captured.selectionRange,
      text: captured.text, canApply: captured.canApply,
      selectedTextAtCapture: captured.fullText == nil ? captured.text : nil)
  }

  func captureClipboardSelection() async throws -> GrammarTextSnapshot {
    let (app, focused) = try Self.focusedContext()
    let candidates = Self.ancestors(of: focused)
    guard !candidates.contains(where: Self.isSecure), !candidates.contains(where: Self.isComposing)
    else {
      throw GrammarCheckError.unavailable
    }
    guard let text = await SelectionMonitorClipboardFallback().selectedTextByCopyCommand() else {
      throw GrammarCheckError.unavailable
    }
    try Task.checkCancellation()
    let (currentApp, currentElement) = try Self.focusedContext()
    guard currentApp.processIdentifier == app.processIdentifier, CFEqual(focused, currentElement)
    else {
      throw GrammarCheckError.changed
    }
    try GrammarText.validate(text)
    return snapshot(
      app: app, element: focused, value: nil,
      range: NSRange(location: 0, length: text.utf16.count), selection: nil, text: text,
      canApply: false)
  }

  func isCurrent(_ snapshot: GrammarTextSnapshot, checkSelection: Bool) -> Bool {
    guard snapshot.targetID == targetID, let target,
      let (app, focused) = try? Self.focusedContext(), app.processIdentifier == snapshot.processID
    else { return false }
    let ancestors = Self.ancestors(of: focused)
    guard ancestors.contains(where: { CFEqual($0, target) }),
      !ancestors.contains(where: Self.isSecure), !ancestors.contains(where: Self.isComposing)
    else { return false }
    if let fullText = snapshot.fullText {
      guard GrammarText.identical(Self.value(target), fullText) else {
        return false
      }
    } else if let selected = snapshot.selectedTextAtCapture {
      guard GrammarText.identical(Self.string(target, kAXSelectedTextAttribute), selected) else {
        return false
      }
    } else if let selected = Self.string(target, kAXSelectedTextAttribute), !selected.isEmpty {
      guard GrammarText.identical(selected, snapshot.text) else { return false }
    }
    return !checkSelection || snapshot.selectionRange == nil
      || Self.range(target, kAXSelectedTextRangeAttribute) == snapshot.selectionRange
  }

  func sourceStatus(_ snapshot: GrammarTextSnapshot, allowPanelFocus: Bool) -> GrammarSourceStatus {
    guard snapshot.targetID == targetID, let target, AXIsProcessTrusted(),
      !IsSecureEventInputEnabled(),
      let front = NSWorkspace.shared.frontmostApplication
    else { return .differentContext }
    let panelOwnsFocus = allowPanelFocus && GrammarWindowController.ownsKeyboardFocus
    guard
      front.processIdentifier == snapshot.processID
        || (panelOwnsFocus && front.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    else { return .differentContext }
    let app = AXUIElementCreateApplication(snapshot.processID)
    if let focused = Self.element(app, kAXFocusedUIElementAttribute) {
      guard Self.ancestors(of: focused).contains(where: { CFEqual($0, target) }) else {
        return .differentContext
      }
    } else if !panelOwnsFocus {
      return .differentContext
    }
    if let targetWindow, let currentWindow = Self.element(app, kAXFocusedWindowAttribute),
      !CFEqual(targetWindow, currentWindow)
    {
      return .differentContext
    }
    let ancestors = Self.ancestors(of: target)
    guard !ancestors.contains(where: Self.isSecure) else { return .differentContext }
    guard !ancestors.contains(where: Self.isComposing) else { return .changed }
    if let fullText = snapshot.fullText {
      return GrammarText.identical(Self.value(target), fullText)
        ? .current : .changed
    }
    if let selected = snapshot.selectedTextAtCapture {
      return GrammarText.identical(Self.string(target, kAXSelectedTextAttribute), selected)
        ? .current : .changed
    }
    if let selected = Self.string(target, kAXSelectedTextAttribute), !selected.isEmpty,
      !GrammarText.identical(selected, snapshot.text)
    {
      return .changed
    }
    return .current
  }

  func prepareSource(_ snapshot: GrammarTextSnapshot, requireUnchanged: Bool) async throws {
    let status = sourceStatus(snapshot, allowPanelFocus: true)
    guard status != .differentContext, !requireUnchanged || status == .current,
      let target, let app = NSRunningApplication(processIdentifier: snapshot.processID)
    else { throw GrammarCheckError.changed }
    GrammarWindowController.releaseKeyboardFocus()
    app.activate(options: [])
    if let targetWindow { AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString) }
    if Self.isSettable(target, kAXFocusedAttribute) {
      AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
    try await Task.sleep(for: .milliseconds(50))
    let restored = sourceStatus(snapshot, allowPanelFocus: false)
    guard restored != .differentContext, !requireUnchanged || restored == .current else {
      throw GrammarCheckError.changed
    }
  }

  func apply(_ suggestion: GrammarSuggestion, to snapshot: GrammarTextSnapshot) async throws
    -> GrammarTextSnapshot
  {
    try await prepareSource(snapshot, requireUnchanged: true)
    guard snapshot.canApply, let target, let fullText = snapshot.fullText,
      isCurrent(snapshot, checkSelection: false),
      Range(suggestion.range, in: snapshot.text) != nil,
      GrammarText.identical(
        (snapshot.text as NSString).substring(with: suggestion.range), suggestion.original)
    else { throw GrammarCheckError.changed }
    let absolute = NSRange(
      location: snapshot.checkedRange.location + suggestion.range.location,
      length: suggestion.range.length)
    guard Range(absolute, in: fullText) != nil else { throw GrammarCheckError.changed }
    let expected = (fullText as NSString).replacingCharacters(
      in: absolute, with: suggestion.replacement)
    var updated = snapshot
    updated.fullText = expected
    updated.text = GrammarText.replacing(snapshot.text, with: [suggestion])
    updated.checkedRange.length += suggestion.replacement.utf16.count - suggestion.range.length
    updated.selectionRange = nil
    let select = {
      guard self.isCurrent(snapshot, checkSelection: false) else { return false }
      var range = CFRange(location: absolute.location, length: absolute.length)
      guard let value = AXValueCreate(.cfRange, &range),
        AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, value)
          == .success
      else { return false }
      return self.isCurrent(snapshot, checkSelection: false)
        && Self.range(target, kAXSelectedTextRangeAttribute) == absolute
    }
    // Writing the selection through Accessibility needs neither keyboard focus nor the clipboard.
    // Editors route it through their normal text input, so it behaves like typing.
    if Self.isSettable(target, kAXSelectedTextAttribute), select(),
      AXUIElementSetAttributeValue(
        target, kAXSelectedTextAttribute as CFString, suggestion.replacement as CFString)
        == .success
    {
      for _ in 0..<8 {
        if isCurrent(updated, checkSelection: false) {
          updated.selectionRange = Self.range(target, kAXSelectedTextRangeAttribute)
          return updated
        }
        try await Task.sleep(for: .milliseconds(50))
      }
      // Some editors accept the write but ignore it. Only an untouched source is safe to paste
      // into; anything else risks applying the edit twice.
      guard isCurrent(snapshot, checkSelection: false) else { throw GrammarCheckError.applyFailed }
    }
    try await clipboard.replaceVerifiedText(
      with: suggestion.replacement, prepare: select,
      verify: { self.isCurrent(updated, checkSelection: false) })
    updated.selectionRange = Self.range(target, kAXSelectedTextRangeAttribute)
    return updated
  }

  func underlineLayout(for suggestions: [GrammarSuggestion], in snapshot: GrammarTextSnapshot)
    -> GrammarUnderlineLayout?
  {
    // Ranges only map onto the editor when its full text was read at capture.
    guard snapshot.targetID == targetID, let target, let fullText = snapshot.fullText,
      var visible = Self.frame(target)
    else { return nil }
    for ancestor in Self.ancestors(of: target).dropFirst() {
      let role = Self.string(ancestor, kAXRoleAttribute)
      guard role == kAXScrollAreaRole || role == "AXWebArea" || role == kAXWindowRole,
        let frame = Self.frame(ancestor)
      else { continue }
      visible = visible.intersection(frame)
    }
    guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
    let length = fullText.utf16.count
    // A hung editor must not stall the main thread for every suggestion.
    let deadline = Date().addingTimeInterval(0.15)
    var marks: [GrammarUnderlineLayout.Mark] = []
    for suggestion in suggestions {
      guard Date() < deadline else { break }
      var absolute = NSRange(
        location: snapshot.checkedRange.location + suggestion.range.location,
        length: suggestion.range.length)
      if absolute.length == 0 {
        // Insertions have no text of their own; mark the character before the gap.
        absolute =
          absolute.location > 0
          ? NSRange(location: absolute.location - 1, length: 1)
          : NSRange(location: 0, length: min(1, length))
      }
      guard absolute.length > 0, NSMaxRange(absolute) <= length else { continue }
      let rects = Self.lineRanges(target, covering: absolute).compactMap { range in
        Self.bounds(target, range).map { $0.intersection(visible) }
      }.filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
      if !rects.isEmpty {
        marks.append(.init(id: suggestion.id, category: suggestion.category, rects: rects))
      }
    }
    return GrammarUnderlineLayout(visibleFrame: visible, marks: marks)
  }

  private func snapshot(
    app: NSRunningApplication, element: AXUIElement, value: String?, range: NSRange,
    selection: NSRange?, text: String, canApply: Bool, selectedTextAtCapture: String? = nil
  ) -> GrammarTextSnapshot {
    if target == nil || !CFEqual(target, element) { targetID = UUID() }
    target = element
    targetWindow = Self.element(element, kAXWindowAttribute)
    return GrammarTextSnapshot(
      targetID: targetID, processID: app.processIdentifier, bundleID: app.bundleIdentifier ?? "",
      fullText: value, checkedRange: range, selectionRange: selection, text: text,
      anchor: Self.anchor(element, range: value == nil ? nil : range), canApply: canApply,
      selectedTextAtCapture: selectedTextAtCapture
    )
  }

  static func focusedContext() throws -> (NSRunningApplication, AXUIElement) {
    guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
      let app = NSWorkspace.shared.frontmostApplication,
      app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      enableAccessibility(for: app),
      let element = element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute)
    else { throw GrammarCheckError.unavailable }
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else {
      throw GrammarCheckError.unavailable
    }
    AXUIElementSetMessagingTimeout(element, 0.25)
    return (app, element)
  }

  private static var accessibilityEnabledPIDs: Set<pid_t> = []

  /// Electron apps build their Accessibility tree only after a client opts in. Without this the
  /// focused input box is invisible. Always returns true so it can sit in a guard chain.
  private static func enableAccessibility(for app: NSRunningApplication) -> Bool {
    let pid = app.processIdentifier
    guard !accessibilityEnabledPIDs.contains(pid) else { return true }
    accessibilityEnabledPIDs = accessibilityEnabledPIDs.filter {
      NSRunningApplication(processIdentifier: $0) != nil
    }
    accessibilityEnabledPIDs.insert(pid)
    guard let bundleURL = app.bundleURL,
      FileManager.default.fileExists(
        atPath: bundleURL.appendingPathComponent(
          "Contents/Frameworks/Electron Framework.framework"
        ).path)
    else { return true }
    AXUIElementSetAttributeValue(
      AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    return true
  }

  static func ancestors(of element: AXUIElement) -> [AXUIElement] {
    var elements = [element]
    for _ in 0..<8 {
      guard let last = elements.last, let parent = self.element(last, kAXParentAttribute),
        !elements.contains(where: { CFEqual($0, parent) })
      else { break }
      elements.append(parent)
    }
    return elements
  }

  static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else {
      return nil
    }
    return result
  }

  static func string(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
  }

  /// Some editors omit AXValue but still expose their text through ranged reads.
  static func value(_ element: AXUIElement) -> String? {
    if let value = string(element, kAXValueAttribute) { return value }
    guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? Int, count > 0,
      count <= 500_000
    else { return nil }
    var range = CFRange(location: 0, length: count)
    var result: CFTypeRef?
    guard let parameter = AXValueCreate(.cfRange, &range),
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result)
        == .success
    else { return nil }
    return result as? String
  }

  static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  static func range(_ element: AXUIElement, _ name: String) -> NSRange? {
    guard let value = attribute(element, name), CFGetTypeID(value) == AXValueGetTypeID() else {
      return nil
    }
    var range = CFRange()
    guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range),
      range.location >= 0, range.length >= 0, range.location <= Int.max - range.length
    else { return nil }
    return NSRange(location: range.location, length: range.length)
  }

  static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable: DarwinBoolean = false
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
      && settable.boolValue
  }

  private static func isEditable(_ element: AXUIElement) -> Bool {
    isSettable(element, kAXValueAttribute) || isSettable(element, kAXSelectedTextAttribute)
      || string(element, kAXSubroleAttribute) == "AXContentEditable"
      || self.element(element, kAXEditableAncestorAttribute) != nil
  }

  private static func isSecure(_ element: AXUIElement) -> Bool {
    string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
      || (attribute(element, "AXProtectedContent") as? Bool == true)
  }

  private static func isComposing(_ element: AXUIElement) -> Bool {
    // Not every editor exposes composition. An unsupported attribute is not a positive signal.
    if let range = range(element, "AXTextInputMarkedRange"), range.length > 0 { return true }
    guard let marked = attribute(element, "AXTextInputMarkedTextMarkerRange") else { return false }
    var length: CFTypeRef?
    if AXUIElementCopyParameterizedAttributeValue(
      element, "AXLengthForTextMarkerRange" as CFString, marked, &length) == .success,
      let count = length as? Int
    {
      return count > 0
    }
    return true
  }

  /// Splits a range at visual line breaks so a wrapped suggestion gets one rect per line.
  private static func lineRanges(_ element: AXUIElement, covering range: NSRange) -> [NSRange] {
    guard
      let first = parameterized(element, kAXLineForIndexParameterizedAttribute, range.location)
        as? Int,
      let last = parameterized(
        element, kAXLineForIndexParameterizedAttribute, NSMaxRange(range) - 1) as? Int,
      last >= first, last - first < 20
    else { return [range] }
    let lines = (first...last).compactMap { line -> NSRange? in
      guard let value = parameterized(element, kAXRangeForLineParameterizedAttribute, line),
        CFGetTypeID(value) == AXValueGetTypeID()
      else { return nil }
      var lineRange = CFRange()
      guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &lineRange) else {
        return nil
      }
      let piece = NSIntersectionRange(
        range, NSRange(location: lineRange.location, length: lineRange.length))
      return piece.length > 0 ? piece : nil
    }
    return lines.isEmpty ? [range] : lines
  }

  private static func parameterized(_ element: AXUIElement, _ name: String, _ index: Int)
    -> CFTypeRef?
  {
    var result: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element, name as CFString, index as CFNumber, &result) == .success
    else { return nil }
    return result
  }

  /// Bounds of a text range, converted to AppKit screen coordinates.
  private static func bounds(_ element: AXUIElement, _ range: NSRange) -> CGRect? {
    var cfRange = CFRange(location: range.location, length: range.length)
    var bounds: CFTypeRef?
    var rect = CGRect.zero
    guard let value = AXValueCreate(.cfRange, &cfRange),
      AXUIElementCopyParameterizedAttributeValue(
        element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
      let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
      AXValueGetValue(unsafeDowncast(bounds, to: AXValue.self), .cgRect, &rect),
      rect.width > 0, rect.height > 0
    else { return nil }
    return appKitRect(rect)
  }

  /// An element's frame, converted to AppKit screen coordinates.
  private static func frame(_ element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = attribute(element, kAXPositionAttribute),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      let sizeValue = attribute(element, kAXSizeAttribute),
      CFGetTypeID(sizeValue) == AXValueGetTypeID(),
      AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
      AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
    else { return nil }
    return appKitRect(CGRect(origin: position, size: size))
  }

  private static func appKitRect(_ rect: CGRect) -> CGRect {
    let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func anchor(_ element: AXUIElement, range: NSRange?) -> CGPoint {
    let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
    if let range {
      var cfRange = CFRange(location: range.location, length: range.length)
      var bounds: CFTypeRef?
      var rect = CGRect.zero
      if let value = AXValueCreate(.cfRange, &cfRange),
        AXUIElementCopyParameterizedAttributeValue(
          element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
        let bounds, CFGetTypeID(bounds) == AXValueGetTypeID(),
        AXValueGetValue(unsafeDowncast(bounds, to: AXValue.self), .cgRect, &rect), rect.height > 0
      {
        return CGPoint(x: rect.midX, y: desktopTop - rect.maxY)
      }
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard let positionValue = attribute(element, kAXPositionAttribute),
      CFGetTypeID(positionValue) == AXValueGetTypeID(),
      let sizeValue = attribute(element, kAXSizeAttribute),
      CFGetTypeID(sizeValue) == AXValueGetTypeID(),
      AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &position),
      AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size)
    else { return NSEvent.mouseLocation }
    return CGPoint(x: position.x + size.width - 20, y: desktopTop - position.y - size.height)
  }
}
