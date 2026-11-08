import AssistenteCore
import AVFoundation
import Observation

/// "Leggi ad alta voce": usa la sintesi vocale del Mac nella lingua dell'app.
/// Tutto sul Mac; premendo di nuovo si ferma.
@MainActor
@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    /// Cosa si sta leggendo (per mostrare "Smetti di leggere" sul pulsante giusto).
    private(set) var speakingID: String?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ text: String, id: String) {
        if isSpeaking {
            let wasSame = speakingID == id
            stop()
            if wasSame { return }
        }
        let utterance = AVSpeechUtterance(string: text)
        let language = L.current.locale.replacingOccurrences(of: "_", with: "-")
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        isSpeaking = true
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        speakingID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false; self.speakingID = nil }
    }
}
