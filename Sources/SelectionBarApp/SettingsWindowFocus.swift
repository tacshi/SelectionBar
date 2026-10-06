import AppKit
import SwiftUI

/// Opening Settings is not a keyboard-navigation action. Leave Tab to choose a control.
struct SettingsWindowFocus: NSViewRepresentable {
  let presentation: Int
  let tab: SelectionBarSettingsTab

  func makeNSView(context: Context) -> FocusView { FocusView() }

  func updateNSView(_ view: FocusView, context: Context) {
    let event = NSApp.currentEvent?.type
    view.update(
      presentation: presentation, tab: tab, keyboardNavigation: event == .keyDown || event == .keyUp
    )
  }

  final class FocusView: NSView {
    private var presentation: Int?
    private var tab: SelectionBarSettingsTab?
    private var pendingReset = true
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    deinit {
      if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
      guard let window else { return }
      observer = NotificationCenter.default.addObserver(
        forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleReset() }
      }
      scheduleReset()
    }

    func update(presentation: Int, tab: SelectionBarSettingsTab, keyboardNavigation: Bool) {
      if self.presentation != presentation || (self.tab != tab && !keyboardNavigation) {
        pendingReset = true
      }
      self.presentation = presentation
      self.tab = tab
      scheduleReset()
    }

    private func scheduleReset() {
      guard pendingReset else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.pendingReset, let window = self.window, window.isKeyWindow else {
          return
        }
        self.pendingReset = false
        window.makeFirstResponder(nil)
      }
    }
  }
}
