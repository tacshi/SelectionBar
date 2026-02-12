import SwiftUI
import Testing

@testable import SelectionBarApp
@testable import SelectionBarCore

@Suite("SelectionBarApp Tests")
@MainActor
struct SelectionBarAppTests {
  @Test("menu bar enable button title reflects enabled state")
  func menuBarEnableButtonTitle() {
    #expect(MenuBarContentView.enableButtonTitle(isEnabled: false) == "Enable")
    #expect(MenuBarContentView.enableButtonTitle(isEnabled: true) == "Disable")
  }

  @Test("APIKeySectionWithTest clear key button is configurable")
  func apiKeySectionClearButtonConfiguration() {
    let defaultSection = APIKeySectionWithTest(
      apiKey: .constant(""),
      isTesting: .constant(false),
      testResult: .constant(nil),
      onTestConnection: { .success("ok") },
      onSaveKey: {},
      onClearKey: {}
    )
    #expect(defaultSection.showClearKeyButton)

    let hiddenClearButtonSection = APIKeySectionWithTest(
      apiKey: .constant(""),
      isTesting: .constant(false),
      testResult: .constant(nil),
      showClearKeyButton: false,
      onTestConnection: { .success("ok") },
      onSaveKey: {},
      onClearKey: {}
    )
    #expect(hiddenClearButtonSection.showClearKeyButton == false)
  }
}
