// Strumento per sviluppatori: prova le funzioni dal terminale.
// Uso:  swift run assistente-cli "Perché il Mac è lento?"
//       swift run assistente-cli --chat "Come faccio uno screenshot?"   (poi altre domande, una per riga)
//       swift run assistente-cli --eval Evals/casi.json   (prove di qualità con il modello vero)
//       swift run assistente-cli --guide "Come mando un file all'iPhone?"  (quale guida verificata si attiva)
//       swift run assistente-cli --prompt "..."   (mostra anche il prompt inviato al modello)
import AssistenteCore
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let showPrompt = args.contains("--prompt")
let chatMode = args.contains("--chat")
let guideOnly = args.contains("--guide")
args.removeAll { $0 == "--prompt" || $0 == "--chat" || $0 == "--guide" }

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

// --eval <file>: prove di qualità (vedi Evals/casi.json).
if let i = CommandLine.arguments.firstIndex(of: "--eval") {
    let path = CommandLine.arguments.indices.contains(i + 1) ? CommandLine.arguments[i + 1] : "Evals/casi.json"
    exit(await Eval.run(path: path) ? 0 : 1)
}

// --guide: mostra solo quale guida verificata si attiva (utile per chi
// aggiunge voci a MacHowTo). Nessuna AI.
if guideOnly {
    let guides = MacHelpChat.guides(for: question)
    print(guides.isEmpty ? "— nessuna guida" : guides.map { "✓ " + $0.prefix(60) + "…" }.joined(separator: "\n"))
    exit(0)
}

let assistant = Assistant()
print("❓ \(question)\n")

do {
    switch try await assistant.prepare(question: question) {
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
    case .choices(let message, let options):
        print(message)
        for o in options { print("  - \(o.label)") }
    case .result(let findings, let request, let chart):
        if let chart {
            for seg in chart.segments { print("▇ \(chart.description(of: seg))") }
            print()
        }
        for f in findings { print("• [\(f.severity)] \(f.title)") }
        if showPrompt { print("\n--- prompt ---\n\(request.prompt)\n--------------") }
        print()
        let advice = Finding.advice(from: findings)
        if case .unavailable(let reason) = assistant.provider.availability {
            print("(\(reason))")
        } else {
        var printed = 0
        for try await partial in assistant.explain(request) {
            // Stampa solo la parte nuova del testo.
            let chars = Array(partial)
            if chars.count > printed {
                print(String(chars[printed...]), terminator: "")
                fflush(stdout)
                printed = chars.count
            }
        }
        print()
        }
        if !advice.isEmpty {
            print("\nCosa puoi fare:")
            for a in advice { print("  → \(a)") }
        }
    }
} catch {
    print("Errore: \(error.localizedDescription)")
    exit(1)
}
