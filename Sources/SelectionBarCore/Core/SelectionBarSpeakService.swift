import AVFoundation

/// Speaks text using AVSpeechSynthesizer with a configurable voice,
/// and supports playing audio data from future API-based TTS providers.
@MainActor
public final class SelectionBarSpeakService: NSObject, AVSpeechSynthesizerDelegate,
  AVAudioPlayerDelegate
{
  private let synthesizer = AVSpeechSynthesizer()
  private var audioPlayer: AVAudioPlayer?
  private var onFinished: (() -> Void)?

  public override init() {
    super.init()
    synthesizer.delegate = self
  }

  public var isSpeaking: Bool {
    synthesizer.isSpeaking || (audioPlayer?.isPlaying ?? false)
  }

  /// Speak the given text using the system AVSpeechSynthesizer.
  /// - Parameters:
  ///   - text: The text to speak.
  ///   - voiceIdentifier: The AVSpeechSynthesisVoice identifier. Empty uses system default.
  ///   - onFinished: Called when speech finishes or is stopped.
  public func speakWithSystem(
    text: String, voiceIdentifier: String, onFinished: @escaping () -> Void
  ) {
    stop()
    self.onFinished = onFinished

    let utterance = AVSpeechUtterance(string: text)
    if !voiceIdentifier.isEmpty,
      let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
    {
      utterance.voice = voice
    }
    synthesizer.speak(utterance)
  }

  /// Play audio data returned by an API-based TTS provider.
  public func playAudioData(_ data: Data, onFinished: @escaping () -> Void) {
    stop()
    self.onFinished = onFinished

    do {
      let player = try AVAudioPlayer(data: data)
      player.delegate = self
      audioPlayer = player
      player.play()
    } catch {
      onFinished()
    }
  }

  /// Stop any in-progress speech or audio playback immediately.
  public func stop() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    if let player = audioPlayer, player.isPlaying {
      player.stop()
    }
    audioPlayer = nil
    onFinished = nil
  }

  /// Returns all available system voices, sorted by language then name.
  public static func availableSystemVoices() -> [SpeakVoiceOption] {
    AVSpeechSynthesisVoice.speechVoices()
      .sorted { lhs, rhs in
        if lhs.language == rhs.language {
          return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.language.localizedCaseInsensitiveCompare(rhs.language) == .orderedAscending
      }
      .map { voice in
        SpeakVoiceOption(
          identifier: voice.identifier,
          name: voice.name,
          language: voice.language,
          qualityLabel: qualityLabel(for: voice.quality)
        )
      }
  }

  private static func qualityLabel(for quality: AVSpeechSynthesisVoiceQuality) -> String? {
    switch quality {
    case .premium:
      return "Premium"
    case .enhanced:
      return "Enhanced"
    default:
      return nil
    }
  }

  // MARK: - AVSpeechSynthesizerDelegate

  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.onFinished?()
      self?.onFinished = nil
    }
  }

  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor [weak self] in
      self?.onFinished?()
      self?.onFinished = nil
    }
  }

  // MARK: - AVAudioPlayerDelegate

  nonisolated public func audioPlayerDidFinishPlaying(
    _ player: AVAudioPlayer,
    successfully flag: Bool
  ) {
    Task { @MainActor [weak self] in
      self?.audioPlayer = nil
      self?.onFinished?()
      self?.onFinished = nil
    }
  }
}

/// A voice option for display in the settings UI.
public struct SpeakVoiceOption: Identifiable, Sendable {
  public let identifier: String
  public let name: String
  public let language: String
  public let qualityLabel: String?

  public var id: String { identifier }

  /// Display name like "Samantha (en-US)" or "Samantha (en-US, Enhanced)".
  public var displayName: String {
    if let qualityLabel {
      return "\(name) (\(language), \(qualityLabel))"
    }
    return "\(name) (\(language))"
  }
}
