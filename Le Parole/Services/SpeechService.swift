import AVFoundation

@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()
    private var voicesByLanguageCode: [String: AVSpeechSynthesisVoice] = [:]
    /// Identifies the latest `speak` request; an older one still waiting for
    /// the audio session is dropped.
    private var speechRequest = 0
    private var pendingUtterances = 0

    /// AVAudioSession calls block on the media server, which on a device can
    /// take tens of milliseconds. Speech starts exactly when a card flips, so
    /// they run here instead of on the main thread; the serial queue keeps
    /// activations and deactivations in the order they were requested.
    private nonisolated static let audioSessionQueue = DispatchQueue(
        label: "SpeechService.audioSession",
        qos: .userInitiated
    )
    /// Only accessed on `audioSessionQueue`.
    private nonisolated(unsafe) static var isAudioSessionConfigured = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, languageCode: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let cachedVoice = voicesByLanguageCode[languageCode] {
            utterance.voice = cachedVoice
        } else {
            let voice = Self.bestVoice(for: languageCode)
            voicesByLanguageCode[languageCode] = voice
            utterance.voice = voice
        }
        utterance.rate = 0.42

        speechRequest += 1
        let request = speechRequest
        pendingUtterances += 1
        Task {
            await Self.onAudioSessionQueue {
                Self.configureAudioSessionIfNeeded()
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            pendingUtterances -= 1
            guard request == speechRequest else { return }
            synthesizer.speak(utterance)
        }
    }

    /// Does the one-time setup of the first utterance ahead of time. Listing
    /// the installed voices takes tens to hundreds of milliseconds, which
    /// otherwise stalls the main thread while the first card animates in.
    func prepare(languageCodes: [String]) async {
        let missing = languageCodes.filter { voicesByLanguageCode[$0] == nil }
        async let configured: Void = Self.onAudioSessionQueue { Self.configureAudioSessionIfNeeded() }
        let identifiers = missing.isEmpty ? [] : await Task.detached(priority: .utility) {
            missing.map { (code: $0, identifier: Self.bestVoice(for: $0)?.identifier) }
        }.value
        for entry in identifiers where voicesByLanguageCode[entry.code] == nil {
            voicesByLanguageCode[entry.code] = entry.identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
                ?? AVSpeechSynthesisVoice(language: entry.code)
        }
        await configured
    }

    private nonisolated static func bestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode.prefix(2)) }
            .max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: languageCode)
    }

    private nonisolated static func onAudioSessionQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            audioSessionQueue.async {
                work()
                continuation.resume()
            }
        }
    }

    /// Call on `audioSessionQueue` only.
    private nonisolated static func configureAudioSessionIfNeeded() {
        // .playback category bypasses the silent switch so speech is always audible
        guard !isAudioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .spokenAudio, options: .duckOthers
            )
            isAudioSessionConfigured = true
        } catch {
            // Retry configuration on the next utterance if the audio session
            // is temporarily unavailable (for example during an interruption).
        }
    }

    func stop() {
        speechRequest += 1
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    // AVSpeechSynthesizer calls its delegate off the main actor; hop back to
    // read the shared synthesizer and release the audio session when idle.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateAudioSessionIfIdle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateAudioSessionIfIdle() }
    }

    private func deactivateAudioSessionIfIdle() {
        if !synthesizer.isSpeaking && pendingUtterances == 0 {
            deactivateAudioSession()
        }
    }

    private func deactivateAudioSession() {
        Self.audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
