import Foundation
import Testing

@testable import SelectionBarCore

@Suite("CustomActionConfig Template Tests")
struct CustomActionTemplatesTests {

  /// Templates whose payload is a prompt sent to an LLM.
  static let promptTemplates: [CustomActionConfig] = [
    CustomActionConfig.createPolishTemplate(),
    CustomActionConfig.createCleanUpTemplate(),
    CustomActionConfig.createActionItemsTemplate(),
    CustomActionConfig.createSummaryTemplate(),
    CustomActionConfig.createBulletPointsTemplate(),
    CustomActionConfig.createEmailDraftTemplate(),
  ]

  static let keyBindingTemplates = CustomActionConfig.createKeyBindingStarterTemplates()
  static let javaScriptTemplates = CustomActionConfig.createJavaScriptStarterTemplates()

  /// Every template shipped by the app, from every catalog entry point.
  static let allTemplates: [CustomActionConfig] =
    promptTemplates + keyBindingTemplates + javaScriptTemplates

  // MARK: - Catalog shape

  @Test("the shipped catalogs are non-empty")
  func catalogsAreNonEmpty() {
    #expect(!CustomActionConfig.createAllBuiltInTemplates().isEmpty)
    #expect(!Self.keyBindingTemplates.isEmpty)
    #expect(!Self.javaScriptTemplates.isEmpty)
  }

  @Test("createAllBuiltInTemplates is a subset of the prompt templates")
  func builtInCatalogIsSubsetOfPromptTemplates() {
    let promptIds = Set(Self.promptTemplates.compactMap(\.templateId))
    for template in CustomActionConfig.createAllBuiltInTemplates() {
      #expect(promptIds.contains(template.templateId ?? ""), "\(template.name)")
    }
  }

  // MARK: - Universal invariants

  @Test("every template has a non-empty name")
  func templatesHaveNames() {
    for template in Self.allTemplates {
      #expect(!template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }

  @Test("every template has a non-empty templateId")
  func templatesHaveTemplateIds() {
    for template in Self.allTemplates {
      let templateId = template.templateId ?? ""
      #expect(
        !templateId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(template.name)")
    }
  }

  @Test("templateIds are unique across every shipped template")
  func templateIdsAreUnique() {
    let ids = Self.allTemplates.compactMap(\.templateId)
    #expect(Set(ids).count == ids.count, "duplicate templateId in \(ids)")
  }

  @Test("template names are unique across every shipped template")
  func templateNamesAreUnique() {
    let names = Self.allTemplates.map(\.name)
    #expect(Set(names).count == names.count, "duplicate name in \(names)")
  }

  @Test("every template is marked built-in and starts disabled")
  func templatesAreBuiltInAndDisabled() {
    for template in Self.allTemplates {
      #expect(template.isBuiltIn, "\(template.name)")
      #expect(!template.isEnabled, "\(template.name)")
    }
  }

  @Test("every template has a unique identifier per instantiation")
  func templatesGetFreshIdentifiers() {
    #expect(
      CustomActionConfig.createPolishTemplate().id != CustomActionConfig.createPolishTemplate().id)
    let ids = Self.allTemplates.map(\.id)
    #expect(Set(ids).count == ids.count)
  }

  @Test("no template declares pipeline steps")
  func templatesHaveNoPipelineSteps() {
    for template in Self.allTemplates {
      #expect(template.pipelineSteps.isEmpty, "\(template.name)")
    }
  }

  @Test("every template resolves a localized name")
  func templatesResolveLocalizedNames() {
    for template in Self.allTemplates {
      #expect(!template.localizedName.isEmpty, "\(template.name)")
    }
  }

  // MARK: - Prompt (LLM) templates

  @Test("prompt templates have a non-empty prompt containing the text placeholder")
  func promptTemplatesHavePrompts() {
    for template in Self.promptTemplates {
      #expect(
        !template.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(template.name)"
      )
      #expect(template.prompt.contains("{{TEXT}}"), "\(template.name)")
    }
  }

  @Test("prompt templates declare a model provider and model id")
  func promptTemplatesDeclareModels() {
    for template in Self.promptTemplates {
      #expect(!template.modelProvider.isEmpty, "\(template.name)")
      #expect(!template.modelId.isEmpty, "\(template.name)")
    }
  }

  // MARK: - JavaScript templates

  @Test("JavaScript templates are the javascript kind")
  func javaScriptTemplatesHaveJavaScriptKind() {
    for template in Self.javaScriptTemplates {
      #expect(template.kind == .javascript, "\(template.name)")
    }
  }

  @Test("JavaScript templates define a transform entry point")
  func javaScriptTemplatesDefineTransform() {
    for template in Self.javaScriptTemplates {
      #expect(
        !template.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(template.name)"
      )
      #expect(template.script.contains("function transform("), "\(template.name)")
    }
  }

  @Test("JavaScript templates ship an icon")
  func javaScriptTemplatesHaveIcons() {
    for template in Self.javaScriptTemplates {
      #expect(template.icon?.value.isEmpty == false, "\(template.name)")
    }
  }

  // MARK: - Key binding templates

  @Test("key binding templates are the keyBinding kind with a parsable binding")
  func keyBindingTemplatesAreValid() {
    for template in Self.keyBindingTemplates {
      #expect(template.kind == .keyBinding, "\(template.name)")
      #expect(!template.keyBinding.isEmpty, "\(template.name)")
      let normalized = SelectionBarKeyboardShortcutParser.normalize(template.keyBinding)
      #expect(normalized == template.keyBinding, "\(template.name) binding \(template.keyBinding)")
    }
  }

  @Test("key binding templates ship an icon and no overrides")
  func keyBindingTemplatesShape() {
    for template in Self.keyBindingTemplates {
      #expect(template.icon?.value.isEmpty == false, "\(template.name)")
      #expect(template.keyBindingOverrides.isEmpty, "\(template.name)")
    }
  }

  // MARK: - Codable round-trip

  @Test("every template round-trips through Codable")
  func templatesRoundTripThroughCodable() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    for template in Self.allTemplates {
      let data = try encoder.encode(template)
      let decoded = try decoder.decode(CustomActionConfig.self, from: data)
      #expect(decoded == template, "\(template.name)")
    }
  }

  @Test("a catalog array round-trips through Codable")
  func catalogRoundTripsThroughCodable() throws {
    let data = try JSONEncoder().encode(Self.allTemplates)
    let decoded = try JSONDecoder().decode([CustomActionConfig].self, from: data)
    #expect(decoded == Self.allTemplates)
  }

  @Test("prompt templates declare the LLM kind")
  func promptTemplatesDeclareLLMKind() {
    // These carry only a prompt and a model; inheriting the initializer's
    // .javascript default would make a template used directly behave as a
    // no-op script instead of calling the model.
    for template in CustomActionConfig.createAllBuiltInTemplates() {
      #expect(template.kind == .llm, "\(template.name) should be an LLM action")
      #expect(!template.prompt.isEmpty)
    }
    #expect(CustomActionConfig.createCleanUpTemplate().kind == .llm)
  }
}
