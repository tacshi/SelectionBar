import AppKit
@preconcurrency import ApplicationServices

enum GrammarMonitorEvent { case input, changed, focus, dismiss }

@MainActor
protocol GrammarMonitoring: AnyObject {
  func start(shortcut: String, onChange: @escaping (GrammarMonitorEvent) -> Void)
  func stop()
}

@MainActor
final class GrammarMonitor: GrammarMonitoring {
  nonisolated(unsafe) private var eventMonitor: Any?
  nonisolated(unsafe) private var appObserver: NSObjectProtocol?
  nonisolated(unsafe) private var observer: AXObserver?
  nonisolated(unsafe) private var registrations: [(AXUIElement, CFString)] = []
  private var observedPID: pid_t?
  private var callback: ((GrammarMonitorEvent) -> Void)?
  private var shortcut: SelectionBarKeyboardShortcut?

  deinit {
    let eventMonitor = eventMonitor
    let appObserver = appObserver
    let observer = observer
    let registrations = registrations
    let cleanup: @MainActor @Sendable () -> Void = {
      if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
      if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
      if let observer {
        for (element, name) in registrations {
          AXObserverRemoveNotification(observer, element, name)
        }
        CFRunLoopRemoveSource(
          CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
      }
    }
    if Thread.isMainThread {
      MainActor.assumeIsolated { cleanup() }
    } else {
      DispatchQueue.main.async(execute: cleanup)
    }
  }

  func start(shortcut: String, onChange: @escaping (GrammarMonitorEvent) -> Void) {
    stop()
    self.shortcut = SelectionBarKeyboardShortcutParser.parse(shortcut)
    callback = onChange
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
      .keyDown, .leftMouseDown, .leftMouseUp, .scrollWheel,
    ]) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self else { return }
        if event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID)
          == Int64(ProcessInfo.processInfo.processIdentifier)
        {
          return
        }
        if event.type == .keyDown {
          let modifiers = event.modifierFlags.intersection([
            .command, .control, .option, .shift, .function,
          ])
          if let shortcut = self.shortcut,
            let parsed = SelectionBarKeyboardShortcutParser.parse(
              keyCode: event.keyCode, flags: event.cgEvent?.flags ?? []),
            shortcut.canonicalString == parsed.canonicalString
          {
            return
          }
          if event.keyCode == 53 && modifiers.isEmpty {
            self.callback?(.dismiss)
            return
          }
        } else if NSApp.windows.contains(where: {
          $0.isVisible && $0.frame.contains(NSEvent.mouseLocation)
        }) {
          return
        }
        self.attachObserver()
        self.callback?(.input)
      }
    }
    appObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] notification in
      let activatedPID =
        (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
        .processIdentifier
      MainActor.assumeIsolated {
        if activatedPID == ProcessInfo.processInfo.processIdentifier,
          GrammarWindowController.ownsKeyboardFocus
        {
          return
        }
        self?.detachObserver()
        self?.attachObserver()
        self?.callback?(.focus)
      }
    }
    attachObserver()
  }

  func stop() {
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
    if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
    appObserver = nil
    detachObserver()
    callback = nil
  }

  private func attachObserver() {
    if GrammarWindowController.ownsKeyboardFocus {
      let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
      if frontPID == observedPID || frontPID == ProcessInfo.processInfo.processIdentifier { return }
    }
    guard let (app, focused) = try? GrammarTextAccess.focusedContext() else {
      detachObserver()
      return
    }
    if observedPID != app.processIdentifier {
      detachObserver()
      var newObserver: AXObserver?
      guard
        AXObserverCreate(
          app.processIdentifier,
          { _, _, notification, context in
            guard let context else { return }
            MainActor.assumeIsolated {
              let owner = Unmanaged<GrammarMonitor>.fromOpaque(context).takeUnretainedValue()
              if notification as String == kAXFocusedUIElementChangedNotification {
                owner.attachFocusedElement()
                owner.callback?(.focus)
              } else {
                owner.callback?(.changed)
              }
            }
          }, &newObserver) == .success, let newObserver
      else { return }
      observer = newObserver
      observedPID = app.processIdentifier
      CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
      add(
        AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementChangedNotification)
    }
    if !registrations.contains(where: { CFEqual($0.0, focused) }) { attachFocusedElement() }
  }

  private func attachFocusedElement() {
    if GrammarWindowController.ownsKeyboardFocus { return }
    guard let observer else { return }
    for (element, name) in registrations
    where name as String != kAXFocusedUIElementChangedNotification {
      AXObserverRemoveNotification(observer, element, name)
    }
    registrations.removeAll { $0.1 as String != kAXFocusedUIElementChangedNotification }
    guard let (_, focused) = try? GrammarTextAccess.focusedContext() else { return }
    for element in GrammarTextAccess.ancestors(of: focused).prefix(3) {
      for notification in [
        kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXMovedNotification,
        kAXResizedNotification,
      ] {
        add(element, notification)
      }
    }
  }

  private func add(_ element: AXUIElement, _ notification: String) {
    guard let observer else { return }
    let name = notification as CFString
    if AXObserverAddNotification(observer, element, name, Unmanaged.passUnretained(self).toOpaque())
      == .success
    {
      registrations.append((element, name))
    }
  }

  private func detachObserver() {
    if let observer {
      for (element, name) in registrations { AXObserverRemoveNotification(observer, element, name) }
      CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    registrations.removeAll()
    observer = nil
    observedPID = nil
  }
}
