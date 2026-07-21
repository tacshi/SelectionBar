import AppKit
import Carbon.HIToolbox
import Foundation
import SelectionBarCore
import SwiftUI

struct ShortcutRecorderField: View {
  @Binding var keyBinding: String
  var width: CGFloat?

  @State private var isRecording = false
  @State private var localMonitor: Any?

  private var displayText: String {
    if isRecording {
      return String(localized: "Press Shortcut")
    }
    let parsed = SelectionBarKeyboardShortcutParser.parse(keyBinding)
    if let parsed {
      return parsed.displayString
    }
    let trimmed = keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? String(localized: "Record Shortcut") : trimmed
  }

  var body: some View {
    HStack(spacing: 6) {
      Button {
        if isRecording {
          stopRecording()
        } else {
          startRecording()
        }
      } label: {
        HStack(spacing: 6) {
          Text(displayText)
            .frame(maxWidth: .infinity, alignment: .leading)
          if isRecording {
            Image(systemName: "record.circle")
              .foregroundStyle(.red)
          }
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .tint(isRecording ? .red : nil)
      .frame(width: width)

      if !keyBinding.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Button {
          keyBinding = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Remove"))
      }
    }
    .onDisappear {
      stopRecording()
    }
  }

  private func startRecording() {
    guard !isRecording else { return }
    isRecording = true

    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
      guard isRecording else { return event }
      guard !event.isARepeat else { return nil }

      if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
        return nil
      }

      if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
        let modifiers = ShortcutRecorderEventMapper.modifierFlags(from: event.modifierFlags)
        if modifiers.isEmpty {
          keyBinding = ""
          stopRecording()
          return nil
        }
      }

      let shortcut = ShortcutRecorderEventMapper.shortcut(from: event)
      guard let shortcut else {
        NSSound.beep()
        return nil
      }

      keyBinding = shortcut.canonicalString
      stopRecording()
      return nil
    }
  }

  private func stopRecording() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    isRecording = false
  }
}

enum ShortcutRecorderEventMapper {
  static func shortcut(from event: NSEvent) -> SelectionBarKeyboardShortcut? {
    let eventFlags = modifierFlags(from: event.modifierFlags)
    return SelectionBarKeyboardShortcutParser.parse(
      keyCode: CGKeyCode(event.keyCode),
      flags: eventFlags
    )
  }

  static func modifierFlags(from modifiers: NSEvent.ModifierFlags) -> CGEventFlags {
    let relevant = modifiers.intersection([.command, .option, .shift, .control, .function])
    var flags: CGEventFlags = []

    if relevant.contains(.command) {
      flags.insert(.maskCommand)
    }
    if relevant.contains(.option) {
      flags.insert(.maskAlternate)
    }
    if relevant.contains(.shift) {
      flags.insert(.maskShift)
    }
    if relevant.contains(.control) {
      flags.insert(.maskControl)
    }
    if relevant.contains(.function) {
      flags.insert(.maskSecondaryFn)
    }

    return flags
  }
}
