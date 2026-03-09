import Foundation

#if canImport(AppKit)
  import AppKit
#endif

public struct CustomActionIcon: Codable, Equatable, Sendable, Hashable {
  public var value: String

  private static let systemSymbolFallbacks: [String: String] = [
    "eraser.xmark": "eraser"
  ]

  public init(value: String) {
    self.value = value
  }

  public var resolvedValue: String {
    guard let fallback = Self.systemSymbolFallbacks[value] else { return value }
    return Self.isSystemSymbolAvailable(value) ? value : fallback
  }

  private static func isSystemSymbolAvailable(_ symbolName: String) -> Bool {
    #if canImport(AppKit)
      NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    #else
      true
    #endif
  }
}

public enum CustomActionKind: String, Codable, CaseIterable, Sendable, Hashable {
  case javascript
  case llm
  case keyBinding

  public var displayName: String {
    switch self {
    case .javascript:
      String(localized: "JavaScript", bundle: .localizedModule)
    case .llm:
      String(localized: "LLM", bundle: .localizedModule)
    case .keyBinding:
      String(localized: "Key Binding", bundle: .localizedModule)
    }
  }
}

public enum CustomActionOutputMode: String, Codable, CaseIterable, Sendable, Hashable {
  case resultWindow
  case inplace

  public var displayName: String {
    switch self {
    case .resultWindow:
      String(localized: "Result Window", bundle: .localizedModule)
    case .inplace:
      String(localized: "Inplace Edit", bundle: .localizedModule)
    }
  }
}

public struct CustomActionKeyBindingOverride: Codable, Equatable, Sendable, Hashable, Identifiable {
  public var bundleID: String
  public var appName: String
  public var keyBinding: String

  public var id: String { bundleID }

  public init(bundleID: String, appName: String, keyBinding: String) {
    self.bundleID = bundleID
    self.appName = appName
    self.keyBinding = keyBinding
  }
}

/// Configuration for a text action.
public struct CustomActionConfig: Codable, Identifiable, Equatable, Sendable, Hashable {
  public static let defaultPromptTemplate = "Process the following text:\n\n{{TEXT}}"
  public static let defaultJavaScriptTemplate = """
    function transform(input) {
      return input;
    }
    """

  public let id: UUID
  public var name: String
  public var prompt: String
  public var modelProvider: String
  public var modelId: String
  public var kind: CustomActionKind
  public var outputMode: CustomActionOutputMode
  public var script: String
  public var keyBinding: String
  public var keyBindingOverrides: [CustomActionKeyBindingOverride]
  public var isEnabled: Bool
  public var isBuiltIn: Bool
  public var templateId: String?
  public var icon: CustomActionIcon?

  /// Localized name for known built-in templates.
  public var localizedName: String {
    guard isBuiltIn, let templateId else { return name }
    switch templateId {
    case "polish": return String(localized: "Polish", bundle: .localizedModule)
    case "cleanup": return String(localized: "Clean Up", bundle: .localizedModule)
    case "action-items": return String(localized: "Extract Actions", bundle: .localizedModule)
    case "summary": return String(localized: "Summarize", bundle: .localizedModule)
    case "bullet-points": return String(localized: "Bulletize", bundle: .localizedModule)
    case "email-draft": return String(localized: "Draft Email", bundle: .localizedModule)
    case "kb-bold": return String(localized: "Bold", bundle: .localizedModule)
    case "kb-italic": return String(localized: "Italic", bundle: .localizedModule)
    case "kb-underline": return String(localized: "Underline", bundle: .localizedModule)
    case "js-trim-normalize":
      return String(localized: "Trim + Normalize Whitespace", bundle: .localizedModule)
    case "js-title-case": return String(localized: "Title Case", bundle: .localizedModule)
    case "js-url-toolkit": return String(localized: "URL Toolkit", bundle: .localizedModule)
    case "js-jwt-decode": return String(localized: "JWT Decode", bundle: .localizedModule)
    case "js-format-json": return String(localized: "Format JSON", bundle: .localizedModule)
    case "js-convert-timestamps":
      return String(localized: "Convert Timestamps", bundle: .localizedModule)
    case "js-clean-escapes":
      return String(localized: "Clean Up Escapes", bundle: .localizedModule)
    case "js-wrap-quote": return String(localized: "Wrap as Quote", bundle: .localizedModule)
    default: return name
    }
  }

  public init(
    id: UUID = UUID(),
    name: String = "Custom Action",
    prompt: String = Self.defaultPromptTemplate,
    modelProvider: String = "openai",
    modelId: String = "gpt-4o-mini",
    kind: CustomActionKind = .javascript,
    outputMode: CustomActionOutputMode = .resultWindow,
    script: String = Self.defaultJavaScriptTemplate,
    keyBinding: String = "",
    keyBindingOverrides: [CustomActionKeyBindingOverride] = [],
    isEnabled: Bool = false,
    isBuiltIn: Bool = false,
    templateId: String? = nil,
    icon: CustomActionIcon? = nil
  ) {
    self.id = id
    self.name = name
    self.prompt = prompt
    self.modelProvider = modelProvider
    self.modelId = modelId
    self.kind = kind
    self.outputMode = outputMode
    self.script = script
    self.keyBinding = keyBinding
    self.keyBindingOverrides = keyBindingOverrides
    self.isEnabled = isEnabled
    self.isBuiltIn = isBuiltIn
    self.templateId = templateId
    self.icon = icon
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case prompt
    case modelProvider
    case modelId
    case kind
    case outputMode
    case script
    case keyBinding
    case keyBindingOverrides
    case isEnabled
    case isBuiltIn
    case templateId
    case icon
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Custom Action"
    prompt =
      try container.decodeIfPresent(String.self, forKey: .prompt) ?? Self.defaultPromptTemplate
    modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider) ?? "openai"
    modelId = try container.decodeIfPresent(String.self, forKey: .modelId) ?? "gpt-4o-mini"
    if let rawKind = try container.decodeIfPresent(String.self, forKey: .kind) {
      kind = CustomActionKind(rawValue: rawKind) ?? .javascript
    } else {
      kind = .javascript
    }
    if let rawOutputMode = try container.decodeIfPresent(String.self, forKey: .outputMode) {
      outputMode = CustomActionOutputMode(rawValue: rawOutputMode) ?? .resultWindow
    } else {
      outputMode = .resultWindow
    }
    script =
      try container.decodeIfPresent(String.self, forKey: .script) ?? Self.defaultJavaScriptTemplate
    keyBinding = try container.decodeIfPresent(String.self, forKey: .keyBinding) ?? ""
    keyBindingOverrides =
      try container.decodeIfPresent(
        [CustomActionKeyBindingOverride].self, forKey: .keyBindingOverrides)
      ?? []
    isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
    isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    templateId = try container.decodeIfPresent(String.self, forKey: .templateId)
    icon = try container.decodeIfPresent(CustomActionIcon.self, forKey: .icon)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(prompt, forKey: .prompt)
    try container.encode(modelProvider, forKey: .modelProvider)
    try container.encode(modelId, forKey: .modelId)
    try container.encode(kind.rawValue, forKey: .kind)
    try container.encode(outputMode.rawValue, forKey: .outputMode)
    try container.encode(script, forKey: .script)
    try container.encode(keyBinding, forKey: .keyBinding)
    try container.encode(keyBindingOverrides, forKey: .keyBindingOverrides)
    try container.encode(isEnabled, forKey: .isEnabled)
    try container.encode(isBuiltIn, forKey: .isBuiltIn)
    try container.encode(templateId, forKey: .templateId)
    try container.encode(icon, forKey: .icon)
  }

  public var defaultIconSFSymbolName: String {
    switch templateId {
    case "polish":
      return "text.badge.checkmark"
    case "cleanup":
      return "eraser"
    case "action-items":
      return "checklist"
    case "summary":
      return "text.alignleft"
    case "bullet-points":
      return "list.bullet"
    case "email-draft":
      return "envelope"
    case "js-url-toolkit":
      return "link"
    case "js-jwt-decode":
      return "key.horizontal"
    case "js-convert-timestamps":
      return "clock.arrow.circlepath"
    case "js-clean-escapes":
      return "eraser.xmark"
    case "kb-bold":
      return "bold"
    case "kb-italic":
      return "italic"
    case "kb-underline":
      return "underline"
    default:
      if kind == .keyBinding {
        return "keyboard"
      }
      return "sparkles"
    }
  }

  public var effectiveIcon: CustomActionIcon {
    if let icon {
      return icon
    }
    return CustomActionIcon(value: defaultIconSFSymbolName)
  }

  public func resolvedKeyBinding(for bundleID: String?) -> String {
    guard kind == .keyBinding else { return keyBinding }
    guard
      let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !bundleID.isEmpty
    else {
      return keyBinding
    }
    guard let override = keyBindingOverrides.first(where: { $0.bundleID == bundleID }) else {
      return keyBinding
    }
    let overrideKeyBinding = override.keyBinding.trimmingCharacters(in: .whitespacesAndNewlines)
    return overrideKeyBinding.isEmpty ? keyBinding : overrideKeyBinding
  }

}
