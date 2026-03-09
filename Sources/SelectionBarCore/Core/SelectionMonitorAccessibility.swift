import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
  subsystem: "com.selectionbar", category: "SelectionMonitorAccessibility")

@MainActor
final class SelectionMonitorAccessibility: SelectionMonitorAccessibilityProviding {
  private let focusedWindowChromeHeight: CGFloat = 40

  @discardableResult
  func checkAccessibilityPermission(promptIfNeeded: Bool) -> Bool {
    let trusted = AXIsProcessTrusted()
    guard !trusted, promptIfNeeded else { return trusted }

    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let nowTrusted = AXIsProcessTrustedWithOptions(options)
    logger.info("AX prompt shown, trusted now: \(nowTrusted, privacy: .public)")
    return nowTrusted
  }

  func isFocusedElementEditable() -> Bool {
    guard AXIsProcessTrusted(), let element = focusedElement() else { return false }
    return isEditable(element)
  }

  func selectedTextFromFocusedHierarchy() -> String? {
    guard let focused = focusedElement() else { return nil }

    for element in elementAndAncestors(startingAt: focused) {
      guard let text = selectedText(from: element) else { continue }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      return trimmed
    }

    logger.debug("AX: could not get selected text from focused element hierarchy")
    return nil
  }

  func isTextContext(at screenPoint: NSPoint) -> Bool {
    guard let element = element(at: screenPoint) else { return false }
    return isTextContextInHierarchy(startingAt: element, allowWindowFallback: false)
  }

  func isCurrentProcessElement(at screenPoint: NSPoint) -> Bool {
    guard let element = element(at: screenPoint) else { return false }
    return isOwnedByCurrentProcess(element)
  }

  func isFocusedElementOwnedByCurrentProcess() -> Bool {
    guard let focused = focusedElement() else { return false }
    return isOwnedByCurrentProcess(focused)
  }

  func isFocusedTextContext() -> Bool {
    guard let focused = focusedElement() else { return false }
    return isTextContextInHierarchy(startingAt: focused, allowWindowFallback: true)
  }

  func hasFocusedTextSelection() -> Bool {
    guard let focused = focusedElement() else { return false }
    return hasTextSelectionInHierarchy(startingAt: focused)
  }

  func hasTextSelection(at screenPoint: NSPoint) -> Bool {
    guard let element = element(at: screenPoint) else { return false }
    return hasTextSelectionInHierarchy(startingAt: element)
  }

  func isPointLikelyInFocusedWindowChrome(at screenPoint: NSPoint, forPID pid: pid_t) -> Bool {
    guard let frame = focusedWindowFrame(forPID: pid) else { return false }
    let accessibilityPoint = accessibilityScreenPoint(from: screenPoint)
    guard frame.contains(accessibilityPoint) else { return false }
    return accessibilityPoint.y <= frame.minY + focusedWindowChromeHeight
  }

  func focusedWindowOrigin(forPID pid: pid_t) -> CGPoint? {
    focusedWindowFrame(forPID: pid)?.origin
  }

  private func focusedWindowFrame(forPID pid: pid_t) -> CGRect? {
    let appElement = AXUIElementCreateApplication(pid)
    var focusedWindowValue: CFTypeRef?
    let focusedWindowResult = AXUIElementCopyAttributeValue(
      appElement,
      kAXFocusedWindowAttribute as CFString,
      &focusedWindowValue
    )
    guard focusedWindowResult == .success,
      let focusedWindowValue,
      CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
    else {
      return nil
    }

    let focusedWindow = unsafeDowncast(focusedWindowValue, to: AXUIElement.self)
    guard
      let origin = cgPointValue(
        from: focusedWindow,
        attribute: kAXPositionAttribute as CFString
      ),
      let size = cgSizeValue(
        from: focusedWindow,
        attribute: kAXSizeAttribute as CFString
      )
    else {
      return nil
    }
    return CGRect(origin: origin, size: size)
  }

  private func focusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedElement: CFTypeRef?
    let focusResult = AXUIElementCopyAttributeValue(
      systemWide,
      kAXFocusedUIElementAttribute as CFString,
      &focusedElement
    )

    guard focusResult == .success, let element = focusedElement else {
      logger.debug(
        "AX: could not get focused element, error: \(focusResult.rawValue, privacy: .public)"
      )
      return nil
    }

    guard CFGetTypeID(element) == AXUIElementGetTypeID() else {
      logger.debug("AX: focused element is not an AXUIElement")
      return nil
    }

    return unsafeDowncast(element, to: AXUIElement.self)
  }

  private func isEditable(_ element: AXUIElement) -> Bool {
    var roleValue: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        == .success,
      let role = roleValue as? String
    else {
      return false
    }

    let nativeTextRoles: Set<String> = [
      kAXTextFieldRole as String,
      kAXTextAreaRole as String,
      kAXComboBoxRole as String,
    ]
    if nativeTextRoles.contains(role) {
      var isSettable: DarwinBoolean = false
      let result = AXUIElementIsAttributeSettable(
        element,
        kAXValueAttribute as CFString,
        &isSettable
      )
      if result == .success && isSettable.boolValue {
        return true
      }
      logger.debug("AX: role \(role, privacy: .public) but value not settable - read-only")
      return false
    }

    var subRoleValue: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRoleValue)
      == .success,
      let subRole = subRoleValue as? String,
      subRole == "AXContentEditable"
    {
      return true
    }

    var isRangeSettable: DarwinBoolean = false
    if AXUIElementIsAttributeSettable(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &isRangeSettable
    ) == .success,
      isRangeSettable.boolValue
    {
      return true
    }

    return false
  }

  private func isOwnedByCurrentProcess(_ element: AXUIElement) -> Bool {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return false }
    return pid == ProcessInfo.processInfo.processIdentifier
  }

  private func element(at screenPoint: NSPoint) -> AXUIElement? {
    guard AXIsProcessTrusted() else { return nil }

    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
      systemWide,
      Float(screenPoint.x),
      Float(screenPoint.y),
      &element
    )
    guard result == .success, let element else { return nil }
    return element
  }

  private func accessibilityScreenPoint(from screenPoint: NSPoint) -> CGPoint {
    let menuBarScreenMaxY =
      NSScreen.screens.first?.frame.maxY
      ?? NSScreen.main?.frame.maxY
      ?? 0
    return CGPoint(x: screenPoint.x, y: menuBarScreenMaxY - screenPoint.y)
  }

  private func isTextContextInHierarchy(startingAt element: AXUIElement, allowWindowFallback: Bool)
    -> Bool
  {
    // When the deepest element at a position is the window itself, the app
    // doesn't expose its content via Accessibility (e.g. GPU-rendered editors
    // like Zed). Treat as potentially text-capable so the clipboard fallback
    // can attempt a synthetic Cmd+C.
    if allowWindowFallback, elementRole(element) == kAXWindowRole as String {
      return true
    }

    for candidate in elementAndAncestors(startingAt: element) {
      if isEditable(candidate) || isTextContextElement(candidate) {
        return true
      }
    }
    return false
  }

  private func hasTextSelectionInHierarchy(startingAt element: AXUIElement) -> Bool {
    for candidate in elementAndAncestors(startingAt: element) {
      if hasTextSelection(candidate) {
        return true
      }
    }
    return false
  }

  private func selectedText(from element: AXUIElement) -> String? {
    var selectedTextValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      &selectedTextValue
    )
    guard result == .success, let selectedTextValue else { return nil }
    return selectedTextValue as? String
  }

  private func elementAndAncestors(startingAt element: AXUIElement, maxDepth: Int = 8)
    -> [AXUIElement]
  {
    var elements: [AXUIElement] = []
    var current: AXUIElement? = element
    var depth = 0

    while let candidate = current, depth < maxDepth {
      elements.append(candidate)
      current = parentElement(of: candidate)
      depth += 1
    }
    return elements
  }

  private func parentElement(of element: AXUIElement) -> AXUIElement? {
    var parentValue: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      element,
      kAXParentAttribute as CFString,
      &parentValue
    )
    guard result == .success,
      let parentValue,
      CFGetTypeID(parentValue) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(parentValue, to: AXUIElement.self)
  }

  private func elementRole(_ element: AXUIElement) -> String? {
    var roleValue: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        == .success
    else { return nil }
    return roleValue as? String
  }

  private func hasTextSelection(_ element: AXUIElement) -> Bool {
    if let text = selectedText(from: element)?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
    {
      return true
    }

    if let range = selectedTextRange(from: element), range.length > 0 {
      return true
    }

    if selectedTextRanges(from: element).contains(where: { $0.length > 0 }) {
      return true
    }

    if let markerRangeLength = selectedTextMarkerRangeLength(from: element),
      markerRangeLength > 0
    {
      return true
    }

    return false
  }

  private func isTextContextElement(_ element: AXUIElement) -> Bool {
    var roleValue: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        == .success,
      let role = roleValue as? String
    else {
      return false
    }

    let textLikeRoles: Set<String> = [
      "AXWebArea",
      "AXStaticText",
      kAXTextFieldRole as String,
      kAXTextAreaRole as String,
      kAXComboBoxRole as String,
    ]
    if textLikeRoles.contains(role) {
      return true
    }

    var subroleValue: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
      == .success,
      let subrole = subroleValue as? String,
      subrole == "AXContentEditable"
    {
      return true
    }

    var selectedRangeValue: AnyObject?
    if AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &selectedRangeValue
    ) == .success {
      return true
    }

    return false
  }

  private func selectedTextRange(from element: AXUIElement) -> CFRange? {
    guard
      let value = attributeValue(
        of: element,
        attribute: kAXSelectedTextRangeAttribute as CFString
      )
    else {
      return nil
    }

    return cfRange(from: value)
  }

  private func selectedTextRanges(from element: AXUIElement) -> [CFRange] {
    guard
      let value = attributeValue(
        of: element,
        attribute: kAXSelectedTextRangesAttribute as CFString
      ),
      let ranges = value as? [Any]
    else {
      return []
    }

    return ranges.compactMap { item in
      cfRange(from: item as CFTypeRef)
    }
  }

  private func selectedTextMarkerRangeLength(from element: AXUIElement) -> Int? {
    guard
      let markerRange = attributeValue(
        of: element,
        attribute: kAXSelectedTextMarkerRangeAttribute as CFString
      ),
      CFGetTypeID(markerRange) == AXTextMarkerRangeGetTypeID()
    else {
      return nil
    }

    var lengthValue: CFTypeRef?
    let result = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXLengthForTextMarkerRangeParameterizedAttribute as CFString,
      markerRange,
      &lengthValue
    )
    guard result == .success,
      let lengthValue,
      CFGetTypeID(lengthValue) == CFNumberGetTypeID()
    else {
      return nil
    }

    var length = 0
    let number = unsafeDowncast(lengthValue, to: CFNumber.self)
    guard CFNumberGetValue(number, .intType, &length) else {
      return nil
    }
    return max(length, 0)
  }

  private func attributeValue(of element: AXUIElement, attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, attribute, &value)
    guard result == .success, let value else { return nil }
    return value
  }

  private func cgPointValue(from element: AXUIElement, attribute: CFString) -> CGPoint? {
    guard let value = attributeValue(of: element, attribute: attribute) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgPoint else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
  }

  private func cgSizeValue(from element: AXUIElement, attribute: CFString) -> CGSize? {
    guard let value = attributeValue(of: element, attribute: attribute) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgSize else { return nil }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
  }

  private func cfRange(from value: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else { return nil }

    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
  }
}
