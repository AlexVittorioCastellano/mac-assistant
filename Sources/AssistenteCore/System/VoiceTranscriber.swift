import AVFoundation
import Foundation
import Speech

/// Trasforma la voce in testo, nella lingua dell'utente, interamente sul Mac
/// (SpeechAnalyzer di Apple: l'audio non viene mai inviato in rete).
///
/// Solo la prima volta, se il modello della lingua non è ancora sul
/// Mac, macOS lo scarica da Apple (è un componente del sistema, come una voce:
/// non contiene dati dell'utente).
public enum VoiceTranscriber {
    /// La lingua dell'utente (quella dell'app).
    static var locale: Locale { L.locale }

    static func makeTranscriber() -> DictationTranscriber {
        // "Dettatura breve": pensata per frasi corte con punteggiatura, come
        // una domanda; "progressiva": il testo compare mentre si parla.
        DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
    }

    /// `true` se il riconoscimento della lingua corrente è disponibile su questo Mac.
    public static func isAvailable() async -> Bool {
        await DictationTranscriber.supportedLocales.contains { $0.identifier == locale.identifier }
    }

    static func ensureModel(for transcriber: DictationTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Trascrive un file audio (usato dai test e dalla CLI).
    public static func transcribe(fileAt url: URL) async throws -> String {
        let transcriber = makeTranscriber()
        try await ensureModel(for: transcriber)
        let collect = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }
        let analyzer = try await SpeechAnalyzer(inputAudioFile: AVAudioFile(forReading: url),
                                                modules: [transcriber], finishAfterFile: true)
        let text = try await collect.value
        // L'analizzatore deve restare in vita finché i risultati non sono finiti.
        withExtendedLifetime(analyzer) {}
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Dettatura dal microfono, dal vivo. Uso: `start` → il testo arriva man mano
/// in `onText` → `stop` restituisce il testo finale.
///
/// Richiede il permesso per il microfono (macOS lo chiede la prima volta).
public final class LiveDictation: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    // Il testo già definitivo e quello provvisorio (che può ancora cambiare).
    private let lock = NSLock()
    private var finalText = ""
    private var volatileText = ""

    public init() {}

    public var currentText: String {
        lock.withLock { (finalText + volatileText).trimmingCharacters(in: .whitespaces) }
    }

    public func start(onText: @escaping @Sendable (String) -> Void) async throws {
        let transcriber = VoiceTranscriber.makeTranscriber()
        try await VoiceTranscriber.ensureModel(for: transcriber)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw AIError(L.t("error.voice.unavailable"))
        }

        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        input = continuation
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let piece = String(result.text.characters)
                    self.lock.withLock {
                        if result.isFinal {
                            self.finalText += piece
                            self.volatileText = ""
                        } else {
                            self.volatileText = piece
                        }
                    }
                    onText(self.currentText)
                }
            } catch {}
        }
        try await analyzer.start(inputSequence: stream)

        // Audio del microfono → formato richiesto dal riconoscimento.
        let mic = engine.inputNode
        let micFormat = mic.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: micFormat, to: format) else {
            throw AIError(L.t("error.voice.noMic"))
        }
        mic.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { buffer, _ in
            let ratio = format.sampleRate / micFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var consumed = false
            converter.convert(to: converted, error: nil) { _, status in
                if consumed { status.pointee = .noDataNow; return nil }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
    }

    /// Ferma l'ascolto e restituisce il testo definitivo.
    public func stop() async -> String {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        input?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        return currentText
    }
}
