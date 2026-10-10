import Foundation
import Testing

@testable import SelectionBarCore

@Suite("Grammar settings")
@MainActor
struct GrammarSettingsTests {
  @Test("Partial and unknown grammar settings use safe defaults")
  func partialSettings() throws {
    let partial = try JSONDecoder().decode(
      GrammarSettings.self, from: Data(#"{"mode":"hotkey"}"#.utf8))
    #expect(partial.mode == .hotkey)
    #expect(partial.englishConvention == .both)
    #expect(partial.shortcut.isEmpty)
    #expect(partial.manualProfile == GrammarWritingProfile())
    let profile = try JSONDecoder().decode(
      GrammarWritingProfile.self, from: Data(#"{"refinement":"future","tone":"future"}"#.utf8))
    #expect(profile == GrammarWritingProfile())
    let future = try JSONDecoder().decode(
      GrammarSettings.self, from: Data(#"{"mode":"future","englishConvention":"future"}"#.utf8))
    #expect(future == GrammarSettings())
  }
  @Test("Old settings default to off; grammar configuration persists without checked text")
  func persistence() throws {
    let name = "GrammarSettingsTests.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(Data(#"{"selectionBarEnabled":true}"#.utf8), forKey: "settings")
    let store = SelectionBarSettingsStore(
      defaults: defaults, storageKey: "settings", keychain: InMemoryKeychain())
    #expect(store.selectionBarEnabled)
    #expect(store.grammar == GrammarSettings())
    store.grammar.mode = .automatic
    store.grammar.shortcut = "cmd+ctrl+g"
    store.grammar.providerID = "openai"
    store.grammar.modelID = "grammar-model"
    store.grammar.englishConvention = .british
    store.grammar.manualProfile = GrammarWritingProfile(refinement: .rewrite, tone: .formal)
    store.grammar.excludedApps = [IgnoredApp(id: "test.app", name: "Test")]
    store.grammar.showsUnderlines = false
    store.flushPendingWrites()
    let restored = SelectionBarSettingsStore(
      defaults: defaults, storageKey: "settings", keychain: InMemoryKeychain())
    #expect(restored.grammar == store.grammar)
    let data = try #require(defaults.data(forKey: "settings"))
    let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let grammar = try #require(payload["grammar"] as? [String: Any])
    #expect(
      Set(grammar.keys) == [
        "mode", "shortcut", "providerID", "modelID", "englishConvention", "excludedApps",
        "manualProfile", "showsUnderlines",
      ])
  }
}
