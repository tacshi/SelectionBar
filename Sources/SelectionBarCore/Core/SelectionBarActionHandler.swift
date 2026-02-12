import AppKit
import Foundation

/// Handles built-in Selection Bar actions.
@MainActor
public final class SelectionBarActionHandler {
    private let openAIClient: SelectionBarOpenAIClient
    private let elevenLabsClient: SelectionBarElevenLabsClient
    private let lookupService: SelectionBarLookupService
    private let clipboardService: SelectionBarClipboardService
    private let speakService: SelectionBarSpeakService
    private var synthesisTask: Task<Void, Never>?

    public convenience init() {
        self.init(
            openAIClient: SelectionBarOpenAIClient(),
            elevenLabsClient: SelectionBarElevenLabsClient(),
            lookupService: SelectionBarLookupService(),
            clipboardService: SelectionBarClipboardService(),
            speakService: SelectionBarSpeakService()
        )
    }

    init(
        openAIClient: SelectionBarOpenAIClient,
        elevenLabsClient: SelectionBarElevenLabsClient = SelectionBarElevenLabsClient(),
        lookupService: SelectionBarLookupService,
        clipboardService: SelectionBarClipboardService,
        speakService: SelectionBarSpeakService = SelectionBarSpeakService()
    ) {
        self.openAIClient = openAIClient
        self.elevenLabsClient = elevenLabsClient
        self.lookupService = lookupService
        self.clipboardService = clipboardService
        self.speakService = speakService
    }

    /// Translate selected text in a dedicated translation app.
    @discardableResult
    public func translateWithApp(text: String, providerId: String) async -> Bool {
        await lookupService.translateWithApp(text: text, providerId: providerId)
    }

    /// Speak selected text using the configured provider and voice.
    public func speak(
        text: String, voiceIdentifier: String, providerId: String,
        onFinished: @escaping () -> Void
    ) {
        if SelectionBarSpeakSystemProvider(rawValue: providerId) != nil {
            speakService.speakWithSystem(
                text: text, voiceIdentifier: voiceIdentifier, onFinished: onFinished)
        } else if SelectionBarSpeakAPIProvider(rawValue: providerId) == .elevenLabs {
            speakWithElevenLabs(text: text, voiceId: voiceIdentifier, onFinished: onFinished)
        } else {
            // Custom provider placeholder — future integration point.
            onFinished()
        }
    }

    /// Speak using ElevenLabs TTS API.
    public func speakWithElevenLabs(
        text: String, voiceId: String, modelId: String = "eleven_v3",
        onFinished: @escaping () -> Void
    ) {
        synthesisTask?.cancel()
        let client = elevenLabsClient
        synthesisTask = Task {
            do {
                let audioData = try await performElevenLabsSynthesis(
                    client: client, text: text, voiceId: voiceId, modelId: modelId)
                guard !Task.isCancelled else { return }
                speakService.playAudioData(audioData, onFinished: onFinished)
            } catch {
                if !Task.isCancelled {
                    onFinished()
                }
            }
        }
    }

    private func performElevenLabsSynthesis(
        client: SelectionBarElevenLabsClient,
        text: String, voiceId: String, modelId: String
    ) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try await client.synthesize(text: text, voiceId: voiceId, modelId: modelId)
        }.value
    }

    /// Stop any in-progress speech.
    public func stopSpeaking() {
        synthesisTask?.cancel()
        synthesisTask = nil
        speakService.stop()
    }

    /// Whether speech is currently in progress.
    public var isSpeaking: Bool {
        speakService.isSpeaking
    }

    /// Process selected text using a configured custom action.
    public func process(
        text: String,
        action: CustomActionConfig,
        settings: SelectionBarSettingsStore
    ) async throws -> String {
        switch action.kind {
        case .llm:
            let prompt = buildPrompt(template: action.prompt, text: text)
            let snapshot = makeProviderSettingsSnapshot(from: settings)
            let result = try await performOpenAICompletion(
                prompt: prompt,
                providerId: action.modelProvider,
                explicitModelId: action.modelId,
                preferTranslationModel: false,
                settingsSnapshot: snapshot,
                temperature: 0.2
            )
            let cleaned = sanitizeLLMOutput(result)
            guard !cleaned.isEmpty else { throw SelectionBarError.emptyResult }
            return cleaned

        case .javascript:
            do {
                let result = try await SelectionBarJavaScriptRunner().run(
                    script: action.script,
                    input: text
                )
                let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty else { throw SelectionBarError.emptyResult }
                return cleaned
            } catch let error as SelectionBarJavaScriptRunnerError {
                throw mapJavaScriptError(error)
            }
        }
    }

    /// Translate selected text through configured translation-capable providers.
    public func translate(
        text: String,
        providerId: String,
        targetLanguageCode: String,
        settings: SelectionBarSettingsStore
    ) async throws -> String {
        let sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else { throw SelectionBarError.emptyResult }

        if providerId == "deepl" {
            return try await performDeepLTranslation(
                text: sourceText,
                targetLanguageCode: targetLanguageCode
            )
        }

        let prompt = buildPrompt(
            template: buildTranslationPrompt(targetLanguageCode: targetLanguageCode),
            text: sourceText
        )

        let snapshot = makeProviderSettingsSnapshot(from: settings)
        let result = try await performOpenAICompletion(
            prompt: prompt,
            providerId: providerId,
            explicitModelId: "",
            preferTranslationModel: true,
            settingsSnapshot: snapshot,
            temperature: 0.1
        )

        let cleaned = sanitizeLLMOutput(result)
        guard !cleaned.isEmpty else { throw SelectionBarError.emptyResult }
        return cleaned
    }

    /// Look up selected text in the configured dictionary app.
    @discardableResult
    public func lookUp(text: String, settings: SelectionBarSettingsStore) -> Bool {
        lookupService.lookUp(text: text, settings: settings)
    }

    /// Search selected text on the web using the configured search engine.
    @discardableResult
    public func searchWeb(text: String, settings: SelectionBarSettingsStore) -> Bool {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }

        guard let url = settings.selectionBarSearchEngine.searchURL(for: query) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }

    /// Returns a normalized URL when text can be interpreted as a web URL.
    public func urlToOpen(text: String) -> URL? {
        lookupService.urlToOpen(text: text)
    }

    /// Open selected text as a URL in the default browser when valid.
    @discardableResult
    public func openURL(text: String) -> Bool {
        lookupService.openURL(text: text)
    }

    /// Replace the currently selected text in the frontmost app with the given text.
    /// Uses clipboard + Cmd+V, then restores the original clipboard contents.
    public func replaceSelectedText(with text: String) async {
        await clipboardService.replaceSelectedText(with: text)
    }

    /// Copies text to the clipboard.
    public func copyToClipboard(_ text: String) {
        clipboardService.copyToClipboard(text)
    }

    /// Cuts the current selection in the frontmost app.
    @discardableResult
    public func cutSelection() -> Bool {
        clipboardService.cutSelection()
    }

    private func buildPrompt(template: String, text: String) -> String {
        template.replacing("{{TEXT}}", with: text)
    }

    private func makeProviderSettingsSnapshot(
        from settings: SelectionBarSettingsStore
    ) -> SelectionBarProviderSettingsSnapshot {
        SelectionBarProviderSettingsSnapshot(
            openAIModel: settings.openAIModel,
            openAITranslationModel: settings.openAITranslationModel,
            openRouterModel: settings.openRouterModel,
            openRouterTranslationModel: settings.openRouterTranslationModel,
            customLLMProviders: settings.customLLMProviders
        )
    }

    private func performOpenAICompletion(
        prompt: String,
        providerId: String,
        explicitModelId: String,
        preferTranslationModel: Bool,
        settingsSnapshot: SelectionBarProviderSettingsSnapshot,
        temperature: Double
    ) async throws -> String {
        let client = openAIClient
        return try await Task.detached(priority: .userInitiated) {
            try await client.complete(
                prompt: prompt,
                providerId: providerId,
                explicitModelId: explicitModelId,
                preferTranslationModel: preferTranslationModel,
                settingsSnapshot: settingsSnapshot,
                temperature: temperature
            )
        }.value
    }

    private func performDeepLTranslation(
        text: String,
        targetLanguageCode: String
    ) async throws -> String {
        let client = openAIClient
        return try await Task.detached(priority: .userInitiated) {
            try await client.translateWithDeepL(
                text: text,
                targetLanguageCode: targetLanguageCode
            )
        }.value
    }

    private func sanitizeLLMOutput(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("```") else { return cleaned }

        guard let firstNewline = cleaned.firstIndex(of: "\n"),
            let closingFence = cleaned.range(of: "```", options: .backwards),
            closingFence.lowerBound > firstNewline
        else {
            return cleaned
        }

        let contentStart = cleaned.index(after: firstNewline)
        cleaned = String(cleaned[contentStart..<closingFence.lowerBound])
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mapJavaScriptError(_ error: SelectionBarJavaScriptRunnerError) -> SelectionBarError
    {
        switch error {
        case .missingScript:
            return .javaScriptMissingScript
        case .syntaxError(let message):
            return .javaScriptSyntaxError(message)
        case .missingTransform:
            return .javaScriptMissingTransform
        case .invalidReturnType:
            return .javaScriptInvalidReturnType
        case .runtimeError(let message):
            return .javaScriptRuntimeError(message)
        case .timeout:
            return .javaScriptTimeout
        }
    }

    private func buildTranslationPrompt(targetLanguageCode: String) -> String {
        let targetLanguageName =
            TranslationLanguageCatalog.targetLanguages.first(where: {
                $0.code == targetLanguageCode
            })?
            .name ?? targetLanguageCode

        return """
            You are a professional translator.

            Target language:
            - Code: \(targetLanguageCode)
            - Name: \(targetLanguageName)

            Source language:
            - Auto-detect from the input text.

            Requirements:
            - Translate faithfully into \(targetLanguageName).
            - The output must be accurate, idiomatic, and natural in \(targetLanguageName).
            - Preserve the original tone, intent, and register (formal/informal).
            - Use domain-standard terminology for technical, business, legal, medical, scientific, and software content when relevant.
            - Keep names, product names, URLs, commands, code, numbers, dates, units, and symbols exact.
            - Do not hallucinate or add information not present in the source.
            - Output only the translated text in plain text format.
            - Do not include explanations, labels, markdown, or code fences.

            Input text:
            {{TEXT}}
            """
    }
}

public enum SelectionBarError: LocalizedError, Sendable, Equatable {
    case providerUnavailable(String)
    case emptyResult
    case invalidResponse
    case httpError(Int, String?)
    case javaScriptMissingScript
    case javaScriptSyntaxError(String)
    case javaScriptMissingTransform
    case javaScriptInvalidReturnType
    case javaScriptRuntimeError(String)
    case javaScriptTimeout

    public var errorDescription: String? {
        switch self {
        case .providerUnavailable(let providerId):
            return "Provider '\(providerId)' is unavailable or not configured."
        case .emptyResult:
            return "Processing returned an empty result."
        case .invalidResponse:
            return "Invalid response from provider."
        case .httpError(let statusCode, let body):
            if let body, !body.isEmpty {
                return "Provider returned HTTP \(statusCode): \(body)"
            }
            return "Provider returned HTTP \(statusCode)."
        case .javaScriptMissingScript:
            return "JavaScript action script is empty."
        case .javaScriptSyntaxError(let message):
            return "JavaScript syntax error: \(message)"
        case .javaScriptMissingTransform:
            return "JavaScript action must define transform(input)."
        case .javaScriptInvalidReturnType:
            return "JavaScript transform(input) must return a string."
        case .javaScriptRuntimeError(let message):
            return "JavaScript runtime error: \(message)"
        case .javaScriptTimeout:
            return "JavaScript action timed out."
        }
    }
}
