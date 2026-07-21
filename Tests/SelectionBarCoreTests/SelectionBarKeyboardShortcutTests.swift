import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SelectionBarKeyboardShortcut Tests")
struct SelectionBarKeyboardShortcutTests {

  // MARK: - Modifier spellings

  @Test("command modifier accepts every documented spelling")
  func commandModifierAliases() {
    for alias in ["cmd", "Cmd", "COMMAND", "command", "meta", "super"] {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("\(alias)+a")
      #expect(shortcut?.canonicalString == "cmd+a", "alias \(alias) failed")
      #expect(shortcut?.eventFlags == .maskCommand)
    }
  }

  @Test("option modifier accepts every documented spelling")
  func optionModifierAliases() {
    for alias in ["opt", "option", "alt", "ALT"] {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("\(alias)+a")
      #expect(shortcut?.canonicalString == "opt+a", "alias \(alias) failed")
      #expect(shortcut?.eventFlags == .maskAlternate)
    }
  }

  @Test("control modifier accepts every documented spelling")
  func controlModifierAliases() {
    for alias in ["ctrl", "control", "ctl", "Control"] {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("\(alias)+a")
      #expect(shortcut?.canonicalString == "ctrl+a", "alias \(alias) failed")
      #expect(shortcut?.eventFlags == .maskControl)
    }
  }

  @Test("function modifier accepts every documented spelling")
  func functionModifierAliases() {
    for alias in ["fn", "function", "globe", "GLOBE"] {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("\(alias)+a")
      #expect(shortcut?.canonicalString == "fn+a", "alias \(alias) failed")
      #expect(shortcut?.eventFlags == .maskSecondaryFn)
    }
  }

  @Test("shift modifier maps to the shift mask")
  func shiftModifier() {
    let shortcut = SelectionBarKeyboardShortcutParser.parse("shift+a")
    #expect(shortcut?.canonicalString == "shift+a")
    #expect(shortcut?.eventFlags == .maskShift)
  }

  @Test("modifier tokens tolerate spaces, underscores and dashes")
  func modifierTokensAreCollapsed() {
    #expect(SelectionBarKeyboardShortcutParser.normalize(" cmd + a ") == "cmd+a")
    #expect(SelectionBarKeyboardShortcutParser.normalize("c-o-m-m-a-n-d+a") == "cmd+a")
    #expect(SelectionBarKeyboardShortcutParser.normalize("con_trol+a") == "ctrl+a")
  }

  // MARK: - Modifier ordering / canonicalization

  @Test("modifiers are emitted in canonical order regardless of input order")
  func modifierOrdering() {
    let expected = "cmd+opt+shift+ctrl+fn+a"
    let inputs = [
      "cmd+opt+shift+ctrl+fn+a",
      "fn+ctrl+shift+opt+cmd+a",
      "shift+fn+cmd+ctrl+alt+a",
    ]
    for input in inputs {
      #expect(SelectionBarKeyboardShortcutParser.normalize(input) == expected, "input \(input)")
    }
  }

  @Test("repeated modifiers collapse to a single occurrence")
  func repeatedModifiers() {
    #expect(SelectionBarKeyboardShortcutParser.normalize("cmd+command+meta+a") == "cmd+a")
  }

  @Test("all five modifier masks combine")
  func allModifierMasks() {
    let shortcut = SelectionBarKeyboardShortcutParser.parse("cmd+opt+shift+ctrl+fn+k")
    let expected: CGEventFlags = [
      .maskCommand, .maskAlternate, .maskShift, .maskControl, .maskSecondaryFn,
    ]
    #expect(shortcut?.eventFlags == expected)
  }

  @Test("canonical strings round-trip through the parser")
  func canonicalRoundTrip() {
    let inputs = [
      "cmd+a",
      "CMD + Shift + Z",
      "ctrl+opt+return",
      "fn+f5",
      "cmd+opt+shift+ctrl+f12",
      "space",
      "cmd+-",
      "shift+pgup",
    ]
    for input in inputs {
      guard let first = SelectionBarKeyboardShortcutParser.parse(input) else {
        Issue.record("expected \(input) to parse")
        continue
      }
      let second = SelectionBarKeyboardShortcutParser.parse(first.canonicalString)
      #expect(second?.canonicalString == first.canonicalString)
      #expect(second?.displayString == first.displayString)
      #expect(second?.keyCode == first.keyCode)
      #expect(second?.eventFlags == first.eventFlags)
    }
  }

  // MARK: - Display strings

  @Test("display strings use spaced plus separators and title-cased tokens")
  func displayStrings() {
    #expect(
      SelectionBarKeyboardShortcutParser.parse("cmd+shift+a")?.displayString == "Cmd + Shift + A")
    #expect(SelectionBarKeyboardShortcutParser.parse("opt+f3")?.displayString == "Opt + F3")
    #expect(
      SelectionBarKeyboardShortcutParser.parse("ctrl+pagedown")?.displayString == "Ctrl + Page Down"
    )
    #expect(
      SelectionBarKeyboardShortcutParser.parse("fn+forward-delete")?.displayString
        == "Fn + Forward Delete")
  }

  @Test("displayString(for:) falls back to trimmed input and empty string")
  func displayStringFallbacks() {
    #expect(SelectionBarKeyboardShortcutParser.displayString(for: "") == "")
    #expect(SelectionBarKeyboardShortcutParser.displayString(for: "   \n ") == "")
    #expect(SelectionBarKeyboardShortcutParser.displayString(for: "  cmd+a  ") == "Cmd + A")
    #expect(SelectionBarKeyboardShortcutParser.displayString(for: " nonsense ") == "nonsense")
  }

  // MARK: - Rejection of malformed input

  @Test("malformed shortcut strings are rejected")
  func malformedInputIsRejected() {
    let invalid = [
      "",
      "   ",
      "\n\t",
      "+",
      "cmd+",
      "+a",
      "cmd++a",
      "cmd",
      "shift",
      "cmd+opt",
      "cmd+a+b",
      "cmd+notakey",
      "garbage",
      "f0",
      "f21",
      "cmd+plus",
      "cmd+ab",
      "cmd+é",
    ]
    for input in invalid {
      #expect(SelectionBarKeyboardShortcutParser.parse(input) == nil, "expected \(input) to fail")
      #expect(
        SelectionBarKeyboardShortcutParser.normalize(input) == nil, "expected \(input) to fail")
    }
  }

  @Test("printable keys require at least one modifier")
  func printableKeysRequireModifier() {
    #expect(SelectionBarKeyboardShortcutParser.parse("a") == nil)
    #expect(SelectionBarKeyboardShortcutParser.parse("1") == nil)
    #expect(SelectionBarKeyboardShortcutParser.parse("/") == nil)
    #expect(SelectionBarKeyboardShortcutParser.parse("minus") == nil)
    #expect(SelectionBarKeyboardShortcutParser.parse("cmd+a") != nil)
  }

  @Test("non-printable keys are allowed without modifiers")
  func nonPrintableKeysAllowedBare() {
    for input in ["f1", "esc", "space", "tab", "return", "left", "home", "pageup"] {
      #expect(SelectionBarKeyboardShortcutParser.parse(input) != nil, "expected \(input) to parse")
      #expect(SelectionBarKeyboardShortcutParser.parse(input)?.eventFlags == [])
    }
  }

  // MARK: - Key-code mapping

  @Test("letters map to their ANSI key codes")
  func letterKeyCodes() {
    let expected: [(String, Int)] = [
      ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("m", kVK_ANSI_M),
      ("q", kVK_ANSI_Q), ("z", kVK_ANSI_Z),
    ]
    for (character, keyCode) in expected {
      #expect(
        SelectionBarKeyboardShortcutParser.parse("cmd+\(character)")?.keyCode == CGKeyCode(keyCode),
        "letter \(character)"
      )
      #expect(
        SelectionBarKeyboardShortcutParser.parse("cmd+\(character.uppercased())")?.keyCode
          == CGKeyCode(keyCode)
      )
    }
  }

  @Test("digits map to their ANSI key codes")
  func digitKeyCodes() {
    let expected: [(String, Int)] = [
      ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("5", kVK_ANSI_5), ("9", kVK_ANSI_9),
    ]
    for (character, keyCode) in expected {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("ctrl+\(character)")
      #expect(shortcut?.keyCode == CGKeyCode(keyCode), "digit \(character)")
      #expect(shortcut?.canonicalString == "ctrl+\(character)")
      #expect(shortcut?.displayString == "Ctrl + \(character)")
    }
  }

  @Test("punctuation keys map by literal and by name")
  func punctuationKeyCodes() {
    let cases: [(literal: String, names: [String], keyCode: Int)] = [
      ("-", ["minus", "dash"], kVK_ANSI_Minus),
      ("=", ["equal", "equals"], kVK_ANSI_Equal),
      ("[", ["leftbracket", "lbracket"], kVK_ANSI_LeftBracket),
      ("]", ["rightbracket", "rbracket"], kVK_ANSI_RightBracket),
      (";", ["semicolon"], kVK_ANSI_Semicolon),
      ("'", ["quote", "apostrophe"], kVK_ANSI_Quote),
      (",", ["comma"], kVK_ANSI_Comma),
      (".", ["period", "dot"], kVK_ANSI_Period),
      ("/", ["slash"], kVK_ANSI_Slash),
      ("\\", ["backslash"], kVK_ANSI_Backslash),
      ("`", ["grave", "backtick"], kVK_ANSI_Grave),
    ]

    for entry in cases {
      let literal = SelectionBarKeyboardShortcutParser.parse("cmd+\(entry.literal)")
      #expect(literal?.keyCode == CGKeyCode(entry.keyCode), "literal \(entry.literal)")
      #expect(literal?.canonicalString == "cmd+\(entry.literal)")

      for name in entry.names {
        let named = SelectionBarKeyboardShortcutParser.parse("cmd+\(name)")
        #expect(named?.keyCode == CGKeyCode(entry.keyCode), "name \(name)")
        #expect(named?.canonicalString == "cmd+\(entry.literal)", "name \(name)")
      }
    }
  }

  @Test("single character f is the letter, not the function key")
  func singleCharacterFIsALetter() {
    #expect(SelectionBarKeyboardShortcutParser.parse("cmd+f")?.keyCode == CGKeyCode(kVK_ANSI_F))
    #expect(SelectionBarKeyboardShortcutParser.parse("cmd+f")?.canonicalString == "cmd+f")
  }

  @Test("function keys F1 through F20 map to their key codes")
  func functionKeyCodes() {
    let expected: [Int: Int] = [
      1: kVK_F1, 2: kVK_F2, 3: kVK_F3, 4: kVK_F4, 5: kVK_F5,
      6: kVK_F6, 7: kVK_F7, 8: kVK_F8, 9: kVK_F9, 10: kVK_F10,
      11: kVK_F11, 12: kVK_F12, 13: kVK_F13, 14: kVK_F14, 15: kVK_F15,
      16: kVK_F16, 17: kVK_F17, 18: kVK_F18, 19: kVK_F19, 20: kVK_F20,
    ]
    for number in 1...20 {
      let shortcut = SelectionBarKeyboardShortcutParser.parse("F\(number)")
      #expect(shortcut?.keyCode == CGKeyCode(expected[number]!), "F\(number)")
      #expect(shortcut?.canonicalString == "f\(number)")
      #expect(shortcut?.displayString == "F\(number)")
    }
  }

  @Test("special keys map to their key codes and canonical tokens")
  func specialKeyCodes() {
    let cases: [(aliases: [String], canonical: String, display: String, keyCode: Int)] = [
      (["return", "enter"], "return", "Return", kVK_Return),
      (["tab"], "tab", "Tab", kVK_Tab),
      (["space", "spacebar"], "space", "Space", kVK_Space),
      (["esc", "escape"], "esc", "Esc", kVK_Escape),
      (["delete", "backspace"], "delete", "Delete", kVK_Delete),
      (["forwarddelete", "forward-delete"], "forwarddelete", "Forward Delete", kVK_ForwardDelete),
      (["left", "leftarrow"], "left", "Left", kVK_LeftArrow),
      (["right", "rightarrow"], "right", "Right", kVK_RightArrow),
      (["up", "uparrow"], "up", "Up", kVK_UpArrow),
      (["down", "downarrow"], "down", "Down", kVK_DownArrow),
      (["home"], "home", "Home", kVK_Home),
      (["end"], "end", "End", kVK_End),
      (["pageup", "pgup", "page up"], "pageup", "Page Up", kVK_PageUp),
      (["pagedown", "pgdown", "page_down"], "pagedown", "Page Down", kVK_PageDown),
    ]

    for entry in cases {
      for alias in entry.aliases {
        let shortcut = SelectionBarKeyboardShortcutParser.parse(alias)
        #expect(shortcut?.keyCode == CGKeyCode(entry.keyCode), "alias \(alias)")
        #expect(shortcut?.canonicalString == entry.canonical, "alias \(alias)")
        #expect(shortcut?.displayString == entry.display, "alias \(alias)")
      }
    }
  }

  // MARK: - parse(keyCode:flags:)

  @Test("parsing from key code and flags produces the canonical string")
  func parseFromKeyCodeAndFlags() {
    let shortcut = SelectionBarKeyboardShortcutParser.parse(
      keyCode: CGKeyCode(kVK_ANSI_A),
      flags: [.maskCommand, .maskShift]
    )
    #expect(shortcut?.canonicalString == "cmd+shift+a")
    #expect(shortcut?.displayString == "Cmd + Shift + A")
    #expect(shortcut?.keyCode == CGKeyCode(kVK_ANSI_A))
    #expect(shortcut?.eventFlags == [.maskCommand, .maskShift])
  }

  @Test("parsing from key code ignores flags outside the supported set")
  func parseFromKeyCodeStripsUnknownFlags() {
    let shortcut = SelectionBarKeyboardShortcutParser.parse(
      keyCode: CGKeyCode(kVK_ANSI_B),
      flags: [.maskCommand, .maskNonCoalesced, .maskAlphaShift]
    )
    #expect(shortcut?.canonicalString == "cmd+b")
    #expect(shortcut?.eventFlags == .maskCommand)
  }

  @Test("every supported flag maps back to its modifier token")
  func parseFromKeyCodeFlagMapping() {
    let cases: [(CGEventFlags, String)] = [
      (.maskCommand, "cmd"),
      (.maskAlternate, "opt"),
      (.maskShift, "shift"),
      (.maskControl, "ctrl"),
      (.maskSecondaryFn, "fn"),
    ]
    for (flag, token) in cases {
      let shortcut = SelectionBarKeyboardShortcutParser.parse(
        keyCode: CGKeyCode(kVK_ANSI_K),
        flags: flag
      )
      #expect(shortcut?.canonicalString == "\(token)+k", "flag \(token)")
    }
  }

  @Test("parsing from key code rejects bare printable keys")
  func parseFromKeyCodeRejectsBarePrintable() {
    #expect(
      SelectionBarKeyboardShortcutParser.parse(keyCode: CGKeyCode(kVK_ANSI_A), flags: []) == nil)
  }

  @Test("parsing from key code allows bare non-printable keys")
  func parseFromKeyCodeAllowsBareSpecialKeys() {
    #expect(
      SelectionBarKeyboardShortcutParser.parse(keyCode: CGKeyCode(kVK_Escape), flags: [])?
        .canonicalString == "esc"
    )
    #expect(
      SelectionBarKeyboardShortcutParser.parse(keyCode: CGKeyCode(kVK_F7), flags: [])?
        .canonicalString == "f7"
    )
    #expect(
      SelectionBarKeyboardShortcutParser.parse(keyCode: CGKeyCode(kVK_Space), flags: [])?
        .canonicalString == "space"
    )
  }

  @Test("parsing from an unmapped key code returns nil")
  func parseFromUnknownKeyCode() {
    #expect(
      SelectionBarKeyboardShortcutParser.parse(keyCode: CGKeyCode(9_999), flags: [.maskCommand])
        == nil)
  }

  @Test("string parsing and key-code parsing agree")
  func stringAndKeyCodeParsingAgree() {
    let cases: [(String, CGKeyCode, CGEventFlags)] = [
      ("cmd+a", CGKeyCode(kVK_ANSI_A), .maskCommand),
      ("opt+shift+7", CGKeyCode(kVK_ANSI_7), [.maskAlternate, .maskShift]),
      ("ctrl+return", CGKeyCode(kVK_Return), .maskControl),
      ("f9", CGKeyCode(kVK_F9), []),
      ("cmd+ctrl+left", CGKeyCode(kVK_LeftArrow), [.maskCommand, .maskControl]),
    ]

    for (raw, keyCode, flags) in cases {
      let fromString = SelectionBarKeyboardShortcutParser.parse(raw)
      let fromKeyCode = SelectionBarKeyboardShortcutParser.parse(keyCode: keyCode, flags: flags)
      #expect(fromString?.canonicalString == fromKeyCode?.canonicalString, "case \(raw)")
      #expect(fromString?.displayString == fromKeyCode?.displayString, "case \(raw)")
      #expect(fromString?.keyCode == fromKeyCode?.keyCode, "case \(raw)")
      #expect(fromString?.eventFlags == fromKeyCode?.eventFlags, "case \(raw)")
    }
  }

  // MARK: - normalize

  @Test("normalize returns the canonical string for valid input")
  func normalizeReturnsCanonicalString() {
    #expect(SelectionBarKeyboardShortcutParser.normalize("COMMAND + SHIFT + Z") == "cmd+shift+z")
    #expect(SelectionBarKeyboardShortcutParser.normalize("Alt+Escape") == "opt+esc")
    #expect(SelectionBarKeyboardShortcutParser.normalize("globe+F13") == "fn+f13")
  }

  @Test("normalize is idempotent")
  func normalizeIsIdempotent() {
    for input in ["Command+Shift+Z", "alt+enter", "globe+f13", "pgdown"] {
      let once = SelectionBarKeyboardShortcutParser.normalize(input)
      let twice = once.flatMap(SelectionBarKeyboardShortcutParser.normalize)
      #expect(once == twice, "input \(input)")
    }
  }
}
