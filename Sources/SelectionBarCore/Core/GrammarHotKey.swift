import Carbon.HIToolbox
import Foundation

@MainActor
protocol GrammarHotKeyRegistering: AnyObject {
  func configure(shortcut: String?, action: @escaping () -> Void) -> String?
}

@MainActor
final class GrammarHotKey: GrammarHotKeyRegistering {
  nonisolated(unsafe) private var hotKey: EventHotKeyRef?
  nonisolated(unsafe) private var handler: EventHandlerRef?
  private var action: (() -> Void)?
  private var isPressed = false

  deinit {
    let key = hotKey
    let eventHandler = handler
    let cleanup: @MainActor @Sendable () -> Void = {
      if let key { UnregisterEventHotKey(key) }
      if let eventHandler { RemoveEventHandler(eventHandler) }
    }
    if Thread.isMainThread {
      MainActor.assumeIsolated { cleanup() }
    } else {
      DispatchQueue.main.async(execute: cleanup)
    }
  }

  func configure(shortcut: String?, action: @escaping () -> Void) -> String? {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = nil
    if let handler { RemoveEventHandler(handler) }
    handler = nil
    isPressed = false
    self.action = action
    guard let shortcut, !shortcut.isEmpty else { return nil }
    guard let parsed = SelectionBarKeyboardShortcutParser.parse(shortcut),
      parsed.eventFlags.contains(.maskCommand) || parsed.eventFlags.contains(.maskControl),
      !parsed.eventFlags.contains(.maskSecondaryFn)
    else {
      return String(
        localized: "Choose a shortcut containing Command or Control, without Fn.",
        bundle: .localizedModule)
    }
    var events = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
    ]
    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var identifier = EventHotKeyID()
        guard
          GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier
          ) == noErr, identifier.signature == 0x5342_4752, identifier.id == 1
        else {
          return OSStatus(eventNotHandledErr)
        }
        return MainActor.assumeIsolated {
          let owner = Unmanaged<GrammarHotKey>.fromOpaque(context).takeUnretainedValue()
          if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
            owner.isPressed = false
          } else if !owner.isPressed {
            owner.isPressed = true
            owner.action?()
          }
          return noErr
        }
      },
      events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler
    )
    var modifiers: UInt32 = 0
    if parsed.eventFlags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
    if parsed.eventFlags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
    if parsed.eventFlags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
    if parsed.eventFlags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
    guard installed == noErr,
      RegisterEventHotKey(
        UInt32(parsed.keyCode), modifiers, EventHotKeyID(signature: 0x5342_4752, id: 1),
        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey
      ) == noErr
    else {
      if let handler { RemoveEventHandler(handler) }
      handler = nil
      return String(
        localized: "Could not register this shortcut. Choose another combination.",
        bundle: .localizedModule)
    }
    return nil
  }
}
