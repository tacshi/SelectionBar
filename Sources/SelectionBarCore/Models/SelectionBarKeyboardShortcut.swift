import Carbon.HIToolbox
import CoreGraphics
import Foundation

public struct SelectionBarKeyboardShortcut: Sendable {
  public let keyCode: CGKeyCode
  public let eventFlags: CGEventFlags
  public let canonicalString: String
  public let displayString: String

  fileprivate init(
    keyCode: CGKeyCode,
    eventFlags: CGEventFlags,
    canonicalString: String,
    displayString: String
  ) {
    self.keyCode = keyCode
    self.eventFlags = eventFlags
    self.canonicalString = canonicalString
    self.displayString = displayString
  }
}

public enum SelectionBarKeyboardShortcutParser {
  public static func parse(_ rawValue: String) -> SelectionBarKeyboardShortcut? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let parts =
      trimmed
      .split(separator: "+", omittingEmptySubsequences: false)
      .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty }) else { return nil }

    var modifiers: Set<ShortcutModifier> = []
    var keyDescriptor: KeyDescriptor?

    for token in parts {
      if let modifier = parseModifier(token) {
        modifiers.insert(modifier)
        continue
      }

      guard keyDescriptor == nil, let parsedKey = parseKey(token) else {
        return nil
      }
      keyDescriptor = parsedKey
    }

    guard let keyDescriptor else { return nil }

    // Require at least one modifier for printable keys so these actions do not
    // accidentally type plain text.
    if modifiers.isEmpty, keyDescriptor.isPrintable {
      return nil
    }

    let orderedModifiers = ShortcutModifier.orderedCases
    let displayParts = orderedModifiers.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.displayToken : nil
    }
    let canonicalParts = orderedModifiers.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.canonicalToken : nil
    }

    let displayString = (displayParts + [keyDescriptor.displayToken]).joined(separator: " + ")
    let canonicalString = (canonicalParts + [keyDescriptor.canonicalToken]).joined(separator: "+")

    return SelectionBarKeyboardShortcut(
      keyCode: keyDescriptor.keyCode,
      eventFlags: eventFlags(for: modifiers),
      canonicalString: canonicalString,
      displayString: displayString
    )
  }

  public static func parse(
    keyCode: CGKeyCode,
    flags: CGEventFlags
  ) -> SelectionBarKeyboardShortcut? {
    guard let keyDescriptor = descriptorForKeyCode(keyCode) else { return nil }
    let modifiers = modifiers(from: flags)

    if modifiers.isEmpty, keyDescriptor.isPrintable {
      return nil
    }

    let orderedModifiers = ShortcutModifier.orderedCases
    let canonicalParts = orderedModifiers.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.canonicalToken : nil
    }
    let displayParts = orderedModifiers.compactMap { modifier in
      modifiers.contains(modifier) ? modifier.displayToken : nil
    }

    let canonicalString = (canonicalParts + [keyDescriptor.canonicalToken]).joined(separator: "+")
    let displayString = (displayParts + [keyDescriptor.displayToken]).joined(separator: " + ")

    return SelectionBarKeyboardShortcut(
      keyCode: keyDescriptor.keyCode,
      eventFlags: eventFlags(for: modifiers),
      canonicalString: canonicalString,
      displayString: displayString
    )
  }

  public static func normalize(_ rawValue: String) -> String? {
    parse(rawValue)?.canonicalString
  }

  public static func displayString(for rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    return parse(trimmed)?.displayString ?? trimmed
  }

  private static func parseModifier(_ token: String) -> ShortcutModifier? {
    let collapsed = collapsedToken(from: token)
    return modifierAliases[collapsed]
  }

  private static func parseKey(_ token: String) -> KeyDescriptor? {
    let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }

    if normalized.count == 1, let character = normalized.first {
      return descriptorForPrintableKey(character)
    }

    let collapsed = collapsedToken(from: normalized)

    if let alias = namedPrintableKeyAliases[collapsed] {
      return descriptorForPrintableKey(alias)
    }

    if let descriptor = specialKeyAliases[collapsed] {
      return descriptor
    }

    if collapsed.hasPrefix("f"),
      let functionNumber = Int(collapsed.dropFirst()),
      let keyCode = functionKeyCodes[functionNumber]
    {
      return KeyDescriptor(
        keyCode: keyCode,
        canonicalToken: "f\(functionNumber)",
        displayToken: "F\(functionNumber)",
        isPrintable: false
      )
    }

    return nil
  }

  private static func descriptorForKeyCode(_ keyCode: CGKeyCode) -> KeyDescriptor? {
    if let descriptor = printableDescriptorsByKeyCode[keyCode] {
      return descriptor
    }

    if let descriptor = specialDescriptorsByKeyCode[keyCode] {
      return descriptor
    }

    if let functionNumber = functionNumbersByKeyCode[keyCode] {
      return KeyDescriptor(
        keyCode: keyCode,
        canonicalToken: "f\(functionNumber)",
        displayToken: "F\(functionNumber)",
        isPrintable: false
      )
    }

    return nil
  }

  private static func descriptorForPrintableKey(_ character: Character) -> KeyDescriptor? {
    guard let keyCode = printableKeyCodes[character] else { return nil }

    let displayToken: String
    if character.isLetter {
      displayToken = String(character).uppercased()
    } else {
      displayToken = String(character)
    }

    return KeyDescriptor(
      keyCode: keyCode,
      canonicalToken: String(character),
      displayToken: displayToken,
      isPrintable: true
    )
  }

  private static func eventFlags(for modifiers: Set<ShortcutModifier>) -> CGEventFlags {
    var flags: CGEventFlags = []
    if modifiers.contains(.command) {
      flags.insert(.maskCommand)
    }
    if modifiers.contains(.option) {
      flags.insert(.maskAlternate)
    }
    if modifiers.contains(.shift) {
      flags.insert(.maskShift)
    }
    if modifiers.contains(.control) {
      flags.insert(.maskControl)
    }
    if modifiers.contains(.function) {
      flags.insert(.maskSecondaryFn)
    }
    return flags
  }

  private static func modifiers(from eventFlags: CGEventFlags) -> Set<ShortcutModifier> {
    var modifiers: Set<ShortcutModifier> = []

    if eventFlags.contains(.maskCommand) {
      modifiers.insert(.command)
    }
    if eventFlags.contains(.maskAlternate) {
      modifiers.insert(.option)
    }
    if eventFlags.contains(.maskShift) {
      modifiers.insert(.shift)
    }
    if eventFlags.contains(.maskControl) {
      modifiers.insert(.control)
    }
    if eventFlags.contains(.maskSecondaryFn) {
      modifiers.insert(.function)
    }

    return modifiers
  }

  private static func collapsedToken(from token: String) -> String {
    token
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: "-", with: "")
  }

  private struct KeyDescriptor {
    let keyCode: CGKeyCode
    let canonicalToken: String
    let displayToken: String
    let isPrintable: Bool
  }

  private enum ShortcutModifier: CaseIterable {
    case command
    case option
    case shift
    case control
    case function

    static let orderedCases: [ShortcutModifier] = [.command, .option, .shift, .control, .function]

    var canonicalToken: String {
      switch self {
      case .command:
        return "cmd"
      case .option:
        return "opt"
      case .shift:
        return "shift"
      case .control:
        return "ctrl"
      case .function:
        return "fn"
      }
    }

    var displayToken: String {
      switch self {
      case .command:
        return "Cmd"
      case .option:
        return "Opt"
      case .shift:
        return "Shift"
      case .control:
        return "Ctrl"
      case .function:
        return "Fn"
      }
    }
  }

  private static let modifierAliases: [String: ShortcutModifier] = [
    "cmd": .command,
    "command": .command,
    "meta": .command,
    "super": .command,
    "opt": .option,
    "option": .option,
    "alt": .option,
    "shift": .shift,
    "ctrl": .control,
    "control": .control,
    "ctl": .control,
    "fn": .function,
    "function": .function,
    "globe": .function,
  ]

  private static let namedPrintableKeyAliases: [String: Character] = [
    "minus": "-",
    "dash": "-",
    "equal": "=",
    "equals": "=",
    "leftbracket": "[",
    "lbracket": "[",
    "rightbracket": "]",
    "rbracket": "]",
    "semicolon": ";",
    "quote": "'",
    "apostrophe": "'",
    "comma": ",",
    "period": ".",
    "dot": ".",
    "slash": "/",
    "backslash": "\\",
    "grave": "`",
    "backtick": "`",
  ]

  private static let specialKeyAliases: [String: KeyDescriptor] = [
    "return": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Return),
      canonicalToken: "return",
      displayToken: "Return",
      isPrintable: false
    ),
    "enter": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Return),
      canonicalToken: "return",
      displayToken: "Return",
      isPrintable: false
    ),
    "tab": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Tab),
      canonicalToken: "tab",
      displayToken: "Tab",
      isPrintable: false
    ),
    "space": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Space),
      canonicalToken: "space",
      displayToken: "Space",
      isPrintable: false
    ),
    "spacebar": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Space),
      canonicalToken: "space",
      displayToken: "Space",
      isPrintable: false
    ),
    "esc": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Escape),
      canonicalToken: "esc",
      displayToken: "Esc",
      isPrintable: false
    ),
    "escape": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Escape),
      canonicalToken: "esc",
      displayToken: "Esc",
      isPrintable: false
    ),
    "delete": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Delete),
      canonicalToken: "delete",
      displayToken: "Delete",
      isPrintable: false
    ),
    "backspace": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Delete),
      canonicalToken: "delete",
      displayToken: "Delete",
      isPrintable: false
    ),
    "forwarddelete": KeyDescriptor(
      keyCode: CGKeyCode(kVK_ForwardDelete),
      canonicalToken: "forwarddelete",
      displayToken: "Forward Delete",
      isPrintable: false
    ),
    "left": KeyDescriptor(
      keyCode: CGKeyCode(kVK_LeftArrow),
      canonicalToken: "left",
      displayToken: "Left",
      isPrintable: false
    ),
    "leftarrow": KeyDescriptor(
      keyCode: CGKeyCode(kVK_LeftArrow),
      canonicalToken: "left",
      displayToken: "Left",
      isPrintable: false
    ),
    "right": KeyDescriptor(
      keyCode: CGKeyCode(kVK_RightArrow),
      canonicalToken: "right",
      displayToken: "Right",
      isPrintable: false
    ),
    "rightarrow": KeyDescriptor(
      keyCode: CGKeyCode(kVK_RightArrow),
      canonicalToken: "right",
      displayToken: "Right",
      isPrintable: false
    ),
    "up": KeyDescriptor(
      keyCode: CGKeyCode(kVK_UpArrow),
      canonicalToken: "up",
      displayToken: "Up",
      isPrintable: false
    ),
    "uparrow": KeyDescriptor(
      keyCode: CGKeyCode(kVK_UpArrow),
      canonicalToken: "up",
      displayToken: "Up",
      isPrintable: false
    ),
    "down": KeyDescriptor(
      keyCode: CGKeyCode(kVK_DownArrow),
      canonicalToken: "down",
      displayToken: "Down",
      isPrintable: false
    ),
    "downarrow": KeyDescriptor(
      keyCode: CGKeyCode(kVK_DownArrow),
      canonicalToken: "down",
      displayToken: "Down",
      isPrintable: false
    ),
    "home": KeyDescriptor(
      keyCode: CGKeyCode(kVK_Home),
      canonicalToken: "home",
      displayToken: "Home",
      isPrintable: false
    ),
    "end": KeyDescriptor(
      keyCode: CGKeyCode(kVK_End),
      canonicalToken: "end",
      displayToken: "End",
      isPrintable: false
    ),
    "pageup": KeyDescriptor(
      keyCode: CGKeyCode(kVK_PageUp),
      canonicalToken: "pageup",
      displayToken: "Page Up",
      isPrintable: false
    ),
    "pgup": KeyDescriptor(
      keyCode: CGKeyCode(kVK_PageUp),
      canonicalToken: "pageup",
      displayToken: "Page Up",
      isPrintable: false
    ),
    "pagedown": KeyDescriptor(
      keyCode: CGKeyCode(kVK_PageDown),
      canonicalToken: "pagedown",
      displayToken: "Page Down",
      isPrintable: false
    ),
    "pgdown": KeyDescriptor(
      keyCode: CGKeyCode(kVK_PageDown),
      canonicalToken: "pagedown",
      displayToken: "Page Down",
      isPrintable: false
    ),
  ]

  private static let functionKeyCodes: [Int: CGKeyCode] = [
    1: CGKeyCode(kVK_F1),
    2: CGKeyCode(kVK_F2),
    3: CGKeyCode(kVK_F3),
    4: CGKeyCode(kVK_F4),
    5: CGKeyCode(kVK_F5),
    6: CGKeyCode(kVK_F6),
    7: CGKeyCode(kVK_F7),
    8: CGKeyCode(kVK_F8),
    9: CGKeyCode(kVK_F9),
    10: CGKeyCode(kVK_F10),
    11: CGKeyCode(kVK_F11),
    12: CGKeyCode(kVK_F12),
    13: CGKeyCode(kVK_F13),
    14: CGKeyCode(kVK_F14),
    15: CGKeyCode(kVK_F15),
    16: CGKeyCode(kVK_F16),
    17: CGKeyCode(kVK_F17),
    18: CGKeyCode(kVK_F18),
    19: CGKeyCode(kVK_F19),
    20: CGKeyCode(kVK_F20),
  ]

  private static let printableKeyCodes: [Character: CGKeyCode] = [
    "a": CGKeyCode(kVK_ANSI_A),
    "b": CGKeyCode(kVK_ANSI_B),
    "c": CGKeyCode(kVK_ANSI_C),
    "d": CGKeyCode(kVK_ANSI_D),
    "e": CGKeyCode(kVK_ANSI_E),
    "f": CGKeyCode(kVK_ANSI_F),
    "g": CGKeyCode(kVK_ANSI_G),
    "h": CGKeyCode(kVK_ANSI_H),
    "i": CGKeyCode(kVK_ANSI_I),
    "j": CGKeyCode(kVK_ANSI_J),
    "k": CGKeyCode(kVK_ANSI_K),
    "l": CGKeyCode(kVK_ANSI_L),
    "m": CGKeyCode(kVK_ANSI_M),
    "n": CGKeyCode(kVK_ANSI_N),
    "o": CGKeyCode(kVK_ANSI_O),
    "p": CGKeyCode(kVK_ANSI_P),
    "q": CGKeyCode(kVK_ANSI_Q),
    "r": CGKeyCode(kVK_ANSI_R),
    "s": CGKeyCode(kVK_ANSI_S),
    "t": CGKeyCode(kVK_ANSI_T),
    "u": CGKeyCode(kVK_ANSI_U),
    "v": CGKeyCode(kVK_ANSI_V),
    "w": CGKeyCode(kVK_ANSI_W),
    "x": CGKeyCode(kVK_ANSI_X),
    "y": CGKeyCode(kVK_ANSI_Y),
    "z": CGKeyCode(kVK_ANSI_Z),
    "0": CGKeyCode(kVK_ANSI_0),
    "1": CGKeyCode(kVK_ANSI_1),
    "2": CGKeyCode(kVK_ANSI_2),
    "3": CGKeyCode(kVK_ANSI_3),
    "4": CGKeyCode(kVK_ANSI_4),
    "5": CGKeyCode(kVK_ANSI_5),
    "6": CGKeyCode(kVK_ANSI_6),
    "7": CGKeyCode(kVK_ANSI_7),
    "8": CGKeyCode(kVK_ANSI_8),
    "9": CGKeyCode(kVK_ANSI_9),
    "`": CGKeyCode(kVK_ANSI_Grave),
    "-": CGKeyCode(kVK_ANSI_Minus),
    "=": CGKeyCode(kVK_ANSI_Equal),
    "[": CGKeyCode(kVK_ANSI_LeftBracket),
    "]": CGKeyCode(kVK_ANSI_RightBracket),
    "\\": CGKeyCode(kVK_ANSI_Backslash),
    ";": CGKeyCode(kVK_ANSI_Semicolon),
    "'": CGKeyCode(kVK_ANSI_Quote),
    ",": CGKeyCode(kVK_ANSI_Comma),
    ".": CGKeyCode(kVK_ANSI_Period),
    "/": CGKeyCode(kVK_ANSI_Slash),
  ]

  private static let printableDescriptorsByKeyCode: [CGKeyCode: KeyDescriptor] = {
    var descriptors: [CGKeyCode: KeyDescriptor] = [:]
    for (character, keyCode) in printableKeyCodes {
      guard let descriptor = descriptorForPrintableKey(character) else { continue }
      descriptors[keyCode] = descriptor
    }
    return descriptors
  }()

  private static let specialDescriptorsByKeyCode: [CGKeyCode: KeyDescriptor] = {
    var descriptors: [CGKeyCode: KeyDescriptor] = [:]
    for descriptor in specialKeyAliases.values where descriptors[descriptor.keyCode] == nil {
      descriptors[descriptor.keyCode] = descriptor
    }
    return descriptors
  }()

  private static let functionNumbersByKeyCode: [CGKeyCode: Int] = {
    var mappings: [CGKeyCode: Int] = [:]
    for (functionNumber, keyCode) in functionKeyCodes {
      mappings[keyCode] = functionNumber
    }
    return mappings
  }()
}
