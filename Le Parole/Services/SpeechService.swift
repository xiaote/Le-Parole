import AVFoundation

final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, languageCode: String) {
        // .playback category bypasses the silent switch so speech is always audible
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode.prefix(2)) }
            .max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = 0.42
        synthesizer.speak(utterance)
    }
}
