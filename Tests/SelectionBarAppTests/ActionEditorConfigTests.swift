import Foundation
import Testing

@testable import SelectionBarApp
@testable import SelectionBarCore

@Suite("Action Editor Config Derivation")
@MainActor
struct ActionEditorConfigTests {
  private func existingConfig(
    id: UUID = UUID(),
    isEnabled: Bool = false,
    templateId: String? = nil
  ) -> CustomActionConfig {
    CustomActionConfig(
      id: id,
      name: "Existing",
      isEnabled: isEnabled,
      isBuiltIn: false,
      templateId: templateId
    )
  }

  // MARK: - Kind branches

  @Test("javascript actions keep the script and clear pipeline steps")
  func javaScriptKind() {
    let config = ActionEditorConfigInput(
      existingConfig: existingConfig(),
      mode: .custom,
      name: "Title Case",
      prompt: "unused prompt",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      actionKind: .javascript,
      outputMode: .inplace,
      script: "function transform(input) { return input }",
      keyBinding: "cmd+b",
      pipelineSteps: [CustomActionPipelineStep(actionID: UUID())],
      includesSourceContext: true
    ).makeConfig()

    #expect(config.kind == .javascript)
    #expect(config.outputMode == .inplace)
    #expect(config.script == "function transform(input) { return input }")
    #expect(config.prompt == "unused prompt")
    #expect(config.modelProvider == "openai")
    #expect(config.modelId == "gpt-4o-mini")
    // Key bindings and source context only apply to their own kinds.
    #expect(config.keyBinding.isEmpty)
    #expect(config.includesSourceContext == false)
    #expect(config.pipelineSteps.isEmpty)
    #expect(config.isBuiltIn == false)
  }

  @Test("llm actions keep prompt, model, and source context")
  func llmKind() {
    let config = ActionEditorConfigInput(
      existingConfig: existingConfig(),
      mode: .custom,
      name: "Summarize",
      prompt: "Summarize {{TEXT}}",
      modelProvider: "openrouter",
      modelId: "anthropic/claude",
      actionKind: .llm,
      outputMode: .resultWindow,
      includesSourceContext: true
    ).makeConfig()

    #expect(config.kind == .llm)
    #expect(config.prompt == "Summarize {{TEXT}}")
    #expect(config.modelProvider == "openrouter")
    #expect(config.modelId == "anthropic/claude")
    #expect(config.includesSourceContext)
    #expect(config.keyBinding.isEmpty)
  }

  @Test("llm actions substitute empty strings for an unselected provider or model")
  func llmKindWithoutSelection() {
    let config = ActionEditorConfigInput(
      mode: .custom,
      name: "Summarize",
      prompt: "Summarize {{TEXT}}",
      modelProvider: nil,
      modelId: nil,
      actionKind: .llm
    ).makeConfig()

    #expect(config.modelProvider.isEmpty)
    #expect(config.modelId.isEmpty)
  }

  @Test("pipeline actions reset prompt, model, and script")
  func pipelineKind() {
    let stepID = UUID()
    let config = ActionEditorConfigInput(
      existingConfig: existingConfig(),
      mode: .custom,
      name: "Chain",
      prompt: "ignored",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      actionKind: .pipeline,
      outputMode: .inplace,
      script: "function transform(input) { return input }",
      pipelineSteps: [CustomActionPipelineStep(actionID: stepID)],
      includesSourceContext: true
    ).makeConfig()

    #expect(config.kind == .pipeline)
    #expect(config.prompt == CustomActionConfig.defaultPromptTemplate)
    #expect(config.modelProvider.isEmpty)
    #expect(config.modelId.isEmpty)
    #expect(config.script == CustomActionConfig.defaultJavaScriptTemplate)
    #expect(config.outputMode == .inplace)
    #expect(config.includesSourceContext == false)
    #expect(config.pipelineSteps.map(\.actionID) == [stepID])
  }

  @Test("built-in key binding mode forces key binding defaults")
  func keyBindingMode() {
    let config = ActionEditorConfigInput(
      existingConfig: existingConfig(),
      mode: .builtInKeyBinding,
      name: "Bold",
      prompt: "ignored",
      modelProvider: "openai",
      modelId: "gpt-4o-mini",
      actionKind: .llm,
      outputMode: .inplace,
      script: "function transform(input) { return input }",
      keyBinding: "cmd+b",
      pipelineSteps: [CustomActionPipelineStep(actionID: UUID())],
      includesSourceContext: true
    ).makeConfig()

    #expect(config.kind == .keyBinding)
    #expect(config.isBuiltIn)
    #expect(config.outputMode == .resultWindow)
    #expect(config.prompt == CustomActionConfig.defaultPromptTemplate)
    #expect(config.script == CustomActionConfig.defaultJavaScriptTemplate)
    #expect(config.modelProvider.isEmpty)
    #expect(config.modelId.isEmpty)
    #expect(config.keyBinding == "cmd+b")
    #expect(config.includesSourceContext == false)
    #expect(config.pipelineSteps.isEmpty)
  }

  // MARK: - Identity carried over from the edited config

  @Test("identity and enablement come from the edited config")
  func preservesIdentity() {
    let id = UUID()
    let config = ActionEditorConfigInput(
      existingConfig: existingConfig(id: id, isEnabled: true),
      mode: .custom,
      name: "Renamed",
      actionKind: .javascript
    ).makeConfig()

    #expect(config.id == id)
    #expect(config.isEnabled)
    #expect(config.name == "Renamed")
    #expect(config.templateId == nil)
  }

  // MARK: - Name normalization

  @Test("blank names fall back to the default action name", arguments: ["", "   ", "\n \t"])
  func blankNameFallsBack(rawName: String) {
    let config = ActionEditorConfigInput(name: rawName, actionKind: .javascript).makeConfig()
    #expect(config.name == String(localized: "Custom Action"))
  }

  @Test("non-blank names are stored verbatim")
  func nonBlankNameKeptVerbatim() {
    let config = ActionEditorConfigInput(name: "  Spaced  ", actionKind: .javascript).makeConfig()
    #expect(config.name == "  Spaced  ")
  }

  // MARK: - Key binding normalization

  @Test("key bindings are canonicalized")
  func keyBindingCanonicalized() {
    let config = ActionEditorConfigInput(
      mode: .builtInKeyBinding,
      keyBinding: "  CMD + B "
    ).makeConfig()

    #expect(config.keyBinding == "cmd+b")
  }

  @Test("unparsable key bindings are kept trimmed")
  func unparsableKeyBindingTrimmed() {
    let config = ActionEditorConfigInput(
      mode: .builtInKeyBinding,
      keyBinding: "  not a shortcut  "
    ).makeConfig()

    #expect(config.keyBinding == "not a shortcut")
  }

  // MARK: - Key binding override normalization

  @Test("overrides drop blank bundle IDs, duplicates, and invalid shortcuts")
  func overrideNormalization() {
    let input = ActionEditorConfigInput(
      mode: .builtInKeyBinding,
      keyBinding: "cmd+b",
      keyBindingOverrides: [
        CustomActionKeyBindingOverride(
          bundleID: "  com.example.first  ",
          appName: "  First  ",
          keyBinding: "  CMD + I "
        ),
        // Duplicate bundle ID: the first entry wins.
        CustomActionKeyBindingOverride(
          bundleID: "com.example.first",
          appName: "Duplicate",
          keyBinding: "cmd+u"
        ),
        // Blank bundle ID.
        CustomActionKeyBindingOverride(
          bundleID: "   ",
          appName: "Blank",
          keyBinding: "cmd+u"
        ),
        // Unparsable shortcut.
        CustomActionKeyBindingOverride(
          bundleID: "com.example.second",
          appName: "Second",
          keyBinding: "nonsense"
        ),
        // Empty shortcut.
        CustomActionKeyBindingOverride(
          bundleID: "com.example.third",
          appName: "Third",
          keyBinding: ""
        ),
      ]
    )

    let config = input.makeConfig()

    #expect(
      config.keyBindingOverrides == [
        CustomActionKeyBindingOverride(
          bundleID: "com.example.first",
          appName: "First",
          keyBinding: "cmd+i"
        )
      ]
    )
  }

  @Test("overrides are discarded outside built-in key binding mode")
  func overridesDiscardedForCustomActions() {
    let config = ActionEditorConfigInput(
      mode: .custom,
      actionKind: .javascript,
      keyBindingOverrides: [
        CustomActionKeyBindingOverride(
          bundleID: "com.example.first",
          appName: "First",
          keyBinding: "cmd+i"
        )
      ]
    ).makeConfig()

    #expect(config.keyBindingOverrides.isEmpty)
  }

  // MARK: - Icon normalization

  @Test("an icon matching the kind default is not persisted")
  func defaultIconIsNotPersisted() {
    let config = ActionEditorConfigInput(
      mode: .custom,
      actionKind: .javascript,
      selectedSFSymbol: "sparkles"
    ).makeConfig()

    #expect(config.icon == nil)
  }

  @Test("a blank icon is not persisted", arguments: ["", "   "])
  func blankIconIsNotPersisted(symbol: String) {
    let config = ActionEditorConfigInput(
      mode: .custom,
      actionKind: .javascript,
      selectedSFSymbol: symbol
    ).makeConfig()

    #expect(config.icon == nil)
  }

  @Test("a custom icon is persisted")
  func customIconIsPersisted() {
    let config = ActionEditorConfigInput(
      mode: .custom,
      actionKind: .javascript,
      selectedSFSymbol: "  bolt  "
    ).makeConfig()

    #expect(config.icon == CustomActionIcon(value: "bolt"))
  }

  @Test("the key binding default icon is not persisted in built-in mode")
  func keyBindingDefaultIconIsNotPersisted() {
    let config = ActionEditorConfigInput(
      mode: .builtInKeyBinding,
      keyBinding: "cmd+b",
      selectedSFSymbol: "keyboard"
    ).makeConfig()

    #expect(config.icon == nil)
  }

  // MARK: - Template factories

  @Test("newAction produces a blank disabled action of the requested kind")
  func newActionFactory() {
    let config = CustomActionConfig.newAction(kind: .pipeline)

    #expect(config.name.isEmpty)
    #expect(config.kind == .pipeline)
    #expect(config.prompt == CustomActionConfig.defaultPromptTemplate)
    #expect(config.script == CustomActionConfig.defaultJavaScriptTemplate)
    #expect(config.modelProvider.isEmpty)
    #expect(config.modelId.isEmpty)
    #expect(config.keyBinding.isEmpty)
    #expect(config.outputMode == .resultWindow)
    #expect(config.isEnabled == false)
    #expect(config.isBuiltIn == false)
    #expect(config.templateId == nil)
    #expect(config.icon == nil)
    #expect(CustomActionConfig.newAction(kind: .keyBinding, isBuiltIn: true).isBuiltIn)
  }

  @Test("from(template:) seeds a key binding action")
  func keyBindingTemplateFactory() {
    let template = CustomActionConfig.createBoldKeyBindingTemplate()
    let config = CustomActionConfig.from(template: template, kind: .keyBinding, isBuiltIn: true)

    #expect(config.name == template.localizedName)
    #expect(config.kind == .keyBinding)
    #expect(config.keyBinding == template.keyBinding)
    #expect(config.icon == template.effectiveIcon)
    #expect(config.isBuiltIn)
    #expect(config.templateId == nil)
    #expect(config.id != template.id)
  }

  @Test("from(template:) seeds a JavaScript action")
  func javaScriptTemplateFactory() {
    let template = CustomActionConfig.createJavaScriptTitleCaseTemplate()
    let config = CustomActionConfig.from(template: template, kind: .javascript)

    #expect(config.name == template.localizedName)
    #expect(config.kind == .javascript)
    #expect(config.outputMode == template.outputMode)
    #expect(config.script == template.script)
    #expect(config.prompt == CustomActionConfig.defaultPromptTemplate)
    #expect(config.modelProvider.isEmpty)
    #expect(config.modelId.isEmpty)
    #expect(config.icon == template.effectiveIcon)
    #expect(config.isBuiltIn == false)
  }

  @Test("from(template:) seeds an LLM action")
  func llmTemplateFactory() {
    let template = CustomActionConfig.createPolishTemplate()
    let config = CustomActionConfig.from(template: template, kind: .llm)

    #expect(config.name == template.localizedName)
    #expect(config.kind == .llm)
    #expect(config.prompt == template.prompt)
    #expect(config.modelProvider == template.modelProvider)
    #expect(config.modelId == template.modelId)
    #expect(config.outputMode == .resultWindow)
    #expect(config.script == CustomActionConfig.defaultJavaScriptTemplate)
    #expect(config.icon == template.effectiveIcon)
    #expect(config.isBuiltIn == false)
  }
}
