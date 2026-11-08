import AssistenteCore
import Foundation

/// Prove di qualità con il modello vero: `assistente-cli --eval Evals/casi.json`.
/// Per ogni caso controlla a quale funzione arriva la domanda, se si attiva
/// una guida verificata e cosa contiene (o non contiene) la risposta.
enum Eval {
    struct File: Decodable { let cases: [Case] }

    struct Case: Decodable {
        var question: String?
        var turns: [String]?
        var intent: String
        var guide: Bool?
        var contains: [String]?
        var containsAny: [String]?
        var notContains: [String]?
        /// Per le conversazioni: se l'ultimo turno deve basarsi su una guida.
        var lastGuide: Bool?

        var allTurns: [String] { turns ?? [question ?? ""] }
    }

    static func run(path: String) async -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            print("Non riesco a leggere \(path)")
            return false
        }
        let assistant = Assistant()
        var failures = 0
        for (n, c) in file.cases.enumerated() {
            let problems = await check(c, assistant: assistant)
            let label = c.allTurns.joined(separator: " → ")
            if problems.isEmpty {
                print("✔ \(n + 1). \(label)")
            } else {
                failures += 1
                print("✘ \(n + 1). \(label)")
                for p in problems { print("    - \(p)") }
            }
        }
        print("\nRisultato: \(file.cases.count - failures)/\(file.cases.count) superati")
        return failures == 0
    }

    /// Esegue un caso e restituisce i problemi trovati (vuoto = superato).
    static func check(_ c: Case, assistant: Assistant) async -> [String] {
        var problems: [String] = []
        var answer = ""
        var intent = ""
        var chat: (any AIChatSession)?
        var chatGuides: [String] = []

        for turn in c.allTurns {
            do {
                let reply = try await assistant.prepare(question: turn, conversationGuides: chatGuides)
                switch reply {
                case .chat(let prompt, let guides):
                    intent = "chat"
                    if turn == c.allTurns.first, let expected = c.guide, expected != !guides.isEmpty {
                        problems.append(expected ? "nessuna guida attivata" : "guida attivata per sbaglio")
                    }
                    let session = chat ?? assistant.makeChatSession()
                    chat = session
                    chatGuides = guides
                    if turn == c.allTurns.last, c.allTurns.count > 1, let expected = c.lastGuide,
                       expected != !guides.isEmpty {
                        problems.append(expected ? "ultimo turno senza guida" : "ultimo turno con una guida non pertinente")
                    }
                    answer = try await collect(session.send(prompt))
                    if MacHelpChat.answerNeedsGuide(answer, guides: guides) {
                        problems.append("scorciatoia diversa dalla guida")
                    }
                case .result(let findings, let request, let chart):
                    intent = chart != nil ? "diskSpace"
                        : findings.contains { $0.id == "overall" } ? "healthCheck"
                        : findings.contains { $0.id == "close" } ? "process" : "slowMac"
                    answer = findings.map(\.title).joined(separator: "\n") + "\n"
                    if let request { answer += try await collect(assistant.explain(request)) }
                case .choices:
                    intent = "processPicker"
                case .message(let text):
                    intent = "message"
                    answer = text
                }
            } catch {
                problems.append("errore: \(error.localizedDescription)")
            }
        }

        if !c.intent.split(separator: "|").contains(Substring(intent)) {
            problems.append("arrivata a «\(intent)» invece di «\(c.intent)»")
        }
        let text = normalize(answer)
        for s in c.contains ?? [] where !text.contains(normalize(s)) {
            problems.append("manca «\(s)»")
        }
        if let any = c.containsAny, !any.contains(where: { text.contains(normalize($0)) }) {
            problems.append("manca almeno uno tra \(any.map { "«\($0)»" }.joined(separator: ", "))")
        }
        // "Non contiene" a inizio parola: "tema" non deve scattare dentro "sistema".
        for s in c.notContains ?? [] where IntentRouter.hasStem(text, normalize(s)) {
            problems.append("contiene «\(s)» (non dovrebbe)")
        }
        if !problems.isEmpty && !answer.isEmpty {
            problems.append("risposta: " + answer.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(300))
        }
        return problems
    }

    static func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var last = ""
        for try await partial in stream { last = partial }
        return last
    }

    /// Minuscole e senza accenti; i simboli dei tasti restano uguali.
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "**", with: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }
}
