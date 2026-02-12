import Foundation

public struct SelectionBarElevenLabsClient: Sendable {
    public typealias APIKeyReader = @Sendable (String) -> String
    public typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let apiKeyReader: APIKeyReader
    private let dataLoader: DataLoader

    public init(
        apiKeyReader: @escaping APIKeyReader = { key in
            KeychainHelper.shared.readString(key: key) ?? ""
        },
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.apiKeyReader = apiKeyReader
        self.dataLoader = dataLoader
    }

    public func synthesize(text: String, voiceId: String, modelId: String) async throws -> Data {
        let apiKey = readAPIKey("elevenlabs_api_key")
        guard !apiKey.isEmpty else {
            throw SelectionBarError.providerUnavailable("elevenlabs")
        }

        guard !voiceId.isEmpty else {
            throw SelectionBarError.providerUnavailable("elevenlabs")
        }

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body = ElevenLabsTTSRequest(
            text: text,
            modelId: modelId,
            voiceSettings: .init(stability: 0.5, similarityBoost: 0.75)
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SelectionBarError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            throw SelectionBarError.httpError(httpResponse.statusCode, errorBody)
        }

        return data
    }

    public func fetchVoices() async throws -> [ElevenLabsVoice] {
        let apiKey = readAPIKey("elevenlabs_api_key")
        guard !apiKey.isEmpty else {
            throw SelectionBarError.providerUnavailable("elevenlabs")
        }

        let url = URL(string: "https://api.elevenlabs.io/v1/voices")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await dataLoader(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SelectionBarError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            throw SelectionBarError.httpError(httpResponse.statusCode, errorBody)
        }

        let parsed = try JSONDecoder().decode(ElevenLabsVoicesResponse.self, from: data)
        return parsed.voices
            .map { ElevenLabsVoice(voiceId: $0.voiceId, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readAPIKey(_ key: String) -> String {
        let value = apiKeyReader(key)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ElevenLabsTTSRequest: Encodable {
    let text: String
    let modelId: String
    let voiceSettings: VoiceSettings

    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
        case voiceSettings = "voice_settings"
    }

    struct VoiceSettings: Encodable {
        let stability: Double
        let similarityBoost: Double

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost = "similarity_boost"
        }
    }
}

private struct ElevenLabsVoicesResponse: Decodable {
    let voices: [Voice]

    struct Voice: Decodable {
        let voiceId: String
        let name: String

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case name
        }
    }
}
