import Foundation
import Testing

@testable import SelectionBarCore

@Suite("SourceContextService Tests")
struct SourceContextServiceTests {
  @Test("isBrowser returns true for Safari")
  func isBrowserSafari() {
    #expect(SourceContextService.isBrowser("com.apple.Safari"))
    #expect(SourceContextService.isBrowser("com.apple.SafariTechnologyPreview"))
  }

  @Test("isBrowser returns true for Chrome variants")
  func isBrowserChrome() {
    #expect(SourceContextService.isBrowser("com.google.Chrome"))
    #expect(SourceContextService.isBrowser("com.google.Chrome.beta"))
    #expect(SourceContextService.isBrowser("com.google.Chrome.dev"))
    #expect(SourceContextService.isBrowser("com.google.Chrome.canary"))
  }

  @Test("isBrowser returns true for other Chromium browsers")
  func isBrowserChromium() {
    #expect(SourceContextService.isBrowser("company.thebrowser.Browser"))  // Arc
    #expect(SourceContextService.isBrowser("com.microsoft.edgemac"))  // Edge
    #expect(SourceContextService.isBrowser("com.brave.Browser"))  // Brave
    #expect(SourceContextService.isBrowser("com.operasoftware.Opera"))  // Opera
    #expect(SourceContextService.isBrowser("com.vivaldi.Vivaldi"))  // Vivaldi
  }

  @Test("isBrowser returns false for non-browser apps")
  func isBrowserNonBrowser() {
    #expect(!SourceContextService.isBrowser("com.apple.TextEdit"))
    #expect(!SourceContextService.isBrowser("com.apple.finder"))
    #expect(!SourceContextService.isBrowser("com.microsoft.VSCode"))
    #expect(!SourceContextService.isBrowser("com.unknown.app"))
    #expect(!SourceContextService.isBrowser(""))
  }
}
