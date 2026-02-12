import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os.log

private let logger = Logger(
  subsystem: "com.selectionbar", category: "SelectionMonitorAccessibility")

@MainActor
final class SelectionMonitorAccessibility {
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
    guard AXIsProcessTrusted() else { return false }
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
      systemWide,
      Float(screenPoint.x),
      Float(screenPoint.y),
      &element
    )
    guard result == .success, let element else { return false }
    return isTextContextInHierarchy(startingAt: element)
  }

  func isCurrentProcessElement(at screenPoint: NSPoint) -> Bool {
    guard AXIsProcessTrusted() else { return false }
    let systemWide = AXUIElementCreateSystemWide()
    var element: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
      systemWide,
      Float(screenPoint.x),
      Float(screenPoint.y),
      &element
    )
    guard result == .success, let element else { return false }
    return isOwnedByCurrentProcess(element)
  }

  func isFocusedElementOwnedByCurrentProcess() -> Bool {
    guard let focused = focusedElement() else { return false }
    return isOwnedByCurrentProcess(focused)
  }

  func isFocusedTextContext() -> Bool {
    guard let focused = focusedElement() else { return false }
    return isTextContextInHierarchy(startingAt: focused)
  }

  func focusedWindowOrigin(forPID pid: pid_t) -> CGPoint? {
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
    var positionValue: CFTypeRef?
    let positionResult = AXUIElementCopyAttributeValue(
      focusedWindow,
      kAXPositionAttribute as CFString,
      &positionValue
    )
    guard positionResult == .success,
      let positionValue,
      CFGetTypeID(positionValue) == AXValueGetTypeID()
    else {
      return nil
    }

    let positionAXValue = unsafeDowncast(positionValue, to: AXValue.self)
    guard AXValueGetType(positionAXValue) == .cgPoint else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(positionAXValue, .cgPoint, &point) else { return nil }
    return point
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
        "AX: could not get focused element, error: \(focusResult.rawValue, privacy: .public)")
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
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
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

  private func isTextContextInHierarchy(startingAt element: AXUIElement) -> Bool {
    for candidate in elementAndAncestors(startingAt: element) {
      if isEditable(candidate) || isTextContextElement(candidate) {
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

  private func isTextContextElement(_ element: AXUIElement) -> Bool {
    var roleValue: AnyObject?
    guard
      AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
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
}
