// Strumento per sviluppatori: prova le funzioni dal terminale.
// Uso:  swift run assistente-cli "Perché il Mac è lento?"
//       swift run assistente-cli --chat "Come faccio uno screenshot?"   (poi altre domande, una per riga)
//       swift run assistente-cli --eval Evals/it.json   (prove di qualità con il modello vero)
//       swift run assistente-cli --messaggio screenshot.png   (o il testo del messaggio)
//       swift run assistente-cli --voce domanda.m4a   (trascrive un file audio, sul Mac)
//       swift run assistente-cli --guide "Come mando un file all'iPhone?"  (quale guida verificata si attiva)
//       swift run assistente-cli --prompt "..."   (mostra anche il prompt inviato al modello)
import AssistenteCore
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let showPrompt = args.contains("--prompt")
let chatMode = args.contains("--chat")
let guideOnly = args.contains("--guide")
args.removeAll { $0 == "--prompt" || $0 == "--chat" || $0 == "--guide" }
if let i = args.firstIndex(of: "--messaggio") { args.removeSubrange(i...) }

/// Stampa una risposta in streaming, solo la parte nuova a ogni passo.
func printStream(_ stream: AsyncThrowingStream<String, Error>) async throws {
    var printed = 0
    for try await partial in stream {
        let chars = Array(partial)
        if chars.count > printed {
            print(String(chars[printed...]), terminator: "")
            fflush(stdout)
            printed = chars.count
        }
    }
    print()
}
let question = args.isEmpty ? Assistant.slowMacQuestion : args.joined(separator: " ")

// --eval <file>: prove di qualità (vedi Evals/it.json).
if let i = CommandLine.arguments.firstIndex(of: "--eval") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "Evals/it.json"
    exit(await Eval.run(path: path) ? 0 : 1)
}

// --messaggio <immagine o testo>: "Spiegami questo messaggio".
var messageInput: String?
if let i = CommandLine.arguments.firstIndex(of: "--messaggio") {
    messageInput = CommandLine.arguments.dropFirst(i + 1).joined(separator: " ")
}

// --voce <file audio>: trascrive (sul Mac) e mostra il testo riconosciuto.
if let i = CommandLine.arguments.firstIndex(of: "--voce"), CommandLine.arguments.indices.contains(i + 1) {
    let start = Date()
    do {
        let text = try await VoiceTranscriber.transcribe(fileAt: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        print("🎤 «\(text)» (\(String(format: "%.1f", Date().timeIntervalSince(start))) s)")
        exit(0)
    } catch {
        print("Errore: \(error.localizedDescription)")
        exit(1)
    }
}

// --guide: mostra solo quale guida verificata si attiva (utile per chi
// aggiunge voci a MacHowTo). Nessuna AI.
if guideOnly {
    let guides = MacHelpChat.guides(for: question)
    print(guides.isEmpty ? "— nessuna guida" : guides.map { "✓ " + $0.prefix(60) + "…" }.joined(separator: "\n"))
    exit(0)
}

let assistant = Assistant()
print("❓ \(messageInput != nil ? Assistant.messageQuestion : question)\n")

do {
    let reply: AssistantReply
    if let input = messageInput {
        if FileManager.default.fileExists(atPath: input), let data = FileManager.default.contents(atPath: input) {
            reply = try await assistant.explainMessage(imageData: data)
        } else {
            reply = assistant.explainMessage(input)
        }
    } else {
        reply = try await assistant.prepare(question: question)
    }
    switch reply {
    case .message(let text):
        print(text)
    case .chat(let prompt, let firstGuides):
        let chat = assistant.makeChatSession()
        var guides = firstGuides
        try await printStream(chat.send(prompt))
        // Con --chat si continua a conversare: una domanda per riga (Ctrl-D per uscire).
        if chatMode {
            while let line = readLine(), !line.isEmpty {
                print("\n❓ \(line)\n")
                var lineGuides = MacHelpChat.guides(for: line)
                if lineGuides.isEmpty && IntentRouter.isFollowUp(line) { lineGuides = guides }  // domanda di seguito
                guides = lineGuides
                try await printStream(chat.send(MacHelpChat.prompt(for: line, guides: lineGuides)))
            }
        }
    case .cleanup(let items):
        // La CLI propone soltanto: spostare file si fa solo dall'app, con conferma.
        if items.isEmpty { print("Non ho trovato file da proporti.") }
        for i in items {
            print("\(i.preselected ? "☑︎" : "☐") \(i.name) — \(ByteCountFormatter.string(fromByteCount: Int64(i.bytes), countStyle: .file)) — \(i.explanation)")
        }
    case .choices(let message, let options):
        print(message)
        for o in options { print("  - \(o.label)") }
    case .result(let findings, let request, let chart):
        if let chart {
            for seg in chart.segments { print("▇ \(chart.description(of: seg))") }
            print()
        }
        for f in findings { print("• [\(f.severity)] \(f.title)") }
        print()
        if let request {
            if showPrompt { print("--- prompt ---\n\(request.prompt)\n--------------\n") }
            if case .unavailable(let reason) = assistant.provider.availability {
                print("(\(reason))")
            } else {
                try await printStream(assistant.explain(request))
            }
        }
        let advice = Finding.advice(from: findings)
        if !advice.isEmpty {
            print("\nCosa puoi fare:")
            for a in advice { print("  → \(a)") }
        }
    }
} catch {
    print("Errore: \(error.localizedDescription)")
    exit(1)
}
