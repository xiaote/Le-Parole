import AVFoundation

final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()
    private var isAudioSessionConfigured = false
    private var voicesByLanguageCode: [String: AVSpeechSynthesisVoice] = [:]

    private init() {}

    func speak(_ text: String, languageCode: String) {
        // .playback category bypasses the silent switch so speech is always audible
        if !isAudioSessionConfigured {
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
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let cachedVoice = voicesByLanguageCode[languageCode] {
            utterance.voice = cachedVoice
        } else {
            let voice = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix(languageCode.prefix(2)) }
                .max(by: { $0.quality.rawValue < $1.quality.rawValue })
                ?? AVSpeechSynthesisVoice(language: languageCode)
            voicesByLanguageCode[languageCode] = voice
            utterance.voice = voice
        }
        utterance.rate = 0.42
        synthesizer.speak(utterance)
    }
}
