// Strumento per sviluppatori: prova le funzioni dal terminale.
// Uso:  swift run assistente-cli "Perché il Mac è lento?"
//       swift run assistente-cli --prompt "..."   (mostra anche il prompt inviato al modello)
import AssistenteCore
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let showPrompt = args.contains("--prompt")
args.removeAll { $0 == "--prompt" }
let question = args.isEmpty ? Assistant.slowMacQuestion : args.joined(separator: " ")

let assistant = Assistant()
print("❓ \(question)\n")

do {
    switch try await assistant.prepare(question: question) {
    case .message(let text):
        print(text)
    case .choices(let message, let options):
        print(message)
        for o in options { print("  - \(o.label)") }
    case .result(let findings, let request):
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
