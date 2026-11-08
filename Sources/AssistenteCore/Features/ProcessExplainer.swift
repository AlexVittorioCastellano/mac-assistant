import Foundation

/// Funzione 2: "Cos'è questo processo?"
///
/// Come per la funzione 1: il codice trova il processo, capisce che tipo è
/// e decide se si può chiudere; l'AI spiega solo a cosa serve.
public enum ProcessExplainer {

    /// Il processo trovato, con i dati per spiegarlo.
    public struct Details: Sendable, Equatable {
        public var group: ProcessGroup
        public var note: String?
    }

    // MARK: Ricerca

    /// Trova un processo per nome tra quelli in esecuzione.
    /// Ordine: nome esatto → nome dell'app (es. "Google Chrome" per i suoi
    /// Helper) → nome che contiene il testo cercato (se c'è un solo risultato).
    public static func find(_ name: String, in samples: [ProcessSample]) -> Details? {
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

        // 1. Nome esatto: chiedere di "Google Chrome Helper" spiega l'Helper.
        var matching = samples.filter { same($0.name, name) }
        // 2. Nome dell'app: "Google Chrome" comprende anche i suoi Helper.
        if matching.isEmpty {
            matching = samples.filter { same(ProcessLister.logicalName($0.name), name) }
        }
        // 3. Nome parziale, solo se non è ambiguo.
        if matching.isEmpty {
            let partial = samples.filter { $0.name.localizedCaseInsensitiveContains(name) }
            if Set(partial.map { ProcessLister.logicalName($0.name) }).count == 1 { matching = partial }
        }
        guard !matching.isEmpty else { return nil }

        // Il processo "principale" (se c'è) decide nome e tipo.
        let logical = ProcessLister.logicalName(matching[0].name)
        let main = matching.first { $0.name == logical } ?? matching[0]
        let displayName = matching.allSatisfy { $0.name == main.name } ? main.name : logical
        let kind = ProcessKind.classifyVerifyingSignature(path: main.path, user: main.user)
        let group = ProcessGroup(
            name: displayName,
            instanceCount: matching.count,
            cpuPercent: matching.reduce(0) { $0 + $1.cpuPercent },
            residentBytes: matching.reduce(0) { $0 + $1.residentBytes },
            isSystem: kind == .macOS,
            pids: matching.map(\.pid),
            path: main.path,
            kind: kind)
        return Details(group: group, note: KnownProcesses.note(for: main.name))
    }

    /// Processi da proporre quando l'utente non ha indicato un nome:
    /// quelli che pesano di più adesso, senza doppioni.
    public static func suggestions(from samples: [ProcessSample], limit: Int = 8) -> [ProcessGroup] {
        // Non proponiamo l'assistente stesso.
        let me = ProcessInfo.processInfo.processIdentifier
        let groups = ProcessLister.group(samples).filter { !$0.pids.contains(me) }
        let byCPU = groups.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit / 2)
        let byMem = groups.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit)
        var seen = Set<String>()
        return Array((byCPU + byMem).filter { seen.insert($0.name).inserted }.prefix(limit))
    }

    // MARK: Cosa mostrare (deciso dal codice)

    public static func findings(for d: Details) -> [Finding] {
        let g = d.group
        var result: [Finding] = []

        switch g.kind {
        case .macOS:
            result.append(.init(id: "kind", severity: .info, title: "Fa parte di macOS"))
            result.append(.init(id: "close", severity: .critical, title: "Non chiuderlo: serve al sistema",
                                advice: g.cpuPercent >= 50
                                    ? "Se continua a usare tanto processore per ore, riavvia il Mac."
                                    : nil))
        case .app(let name):
            result.append(.init(id: "kind", severity: .info, title: "È l'app «\(name)»"))
            result.append(.init(id: "close", severity: .ok, title: "Puoi chiuderla quando vuoi",
                                advice: "Per chiuderla: salva il lavoro, poi premi ⌘Q mentre sei nell'app."))
        case .appComponent(let app):
            result.append(.init(id: "kind", severity: .info, title: "Fa parte dell'app «\(app)»"))
            result.append(.init(id: "close", severity: .info, title: "Non chiuderlo da solo: se serve, chiudi «\(app)»",
                                advice: "Per chiudere «\(app)»: salva il lavoro, poi premi ⌘Q mentre sei nell'app."))
        case .background:
            result.append(.init(id: "kind", severity: .info, title: "È un programma in background installato da un'altra app"))
            result.append(.init(id: "close", severity: .warning, title: "Chiudilo solo se sai a cosa serve: spesso si riavvia da solo",
                                advice: "Puoi vedere e disattivare i programmi in background in Impostazioni di Sistema → Generali → Elementi login."))
        case .unknown:
            result.append(.init(id: "kind", severity: .info, title: "Non riesco a capire da dove viene"))
            result.append(.init(id: "close", severity: .warning, title: "Meglio non chiuderlo se non sai cos'è"))
        }

        var usage = "Adesso usa \(Fmt.percent(g.cpuPercent)) del processore e \(Fmt.size(g.residentBytes)) di memoria"
        if g.instanceCount > 1 { usage += " (\(g.instanceCount) copie)" }
        result.append(.init(id: "usage", severity: .info, title: usage))
        return result
    }

    // MARK: Richiesta all'AI

    public static func request(question: String, details d: Details) -> AIRequest {
        let g = d.group
        let kind = switch g.kind {
            case .macOS: "fa parte di macOS"
            case .app(let name): "è l'app «\(name)»"
            case .appComponent(let app): "è un componente interno dell'app «\(app)»"
            case .background: "è un programma in background installato da terzi"
            case .unknown: "sconosciuto"
        }
        let verdict = findings(for: d).first { $0.id == "close" }?.title ?? ""

        var prompt = """
        Domanda dell'utente: \(question)

        Processo: «\(g.name)»
        Tipo (deciso dall'app): \(kind)
        Si può chiudere? (deciso dall'app): \(verdict)
        """
        if let note = d.note {
            prompt += "\nCosa fa (informazione sicura): \(note)"
        } else if let path = g.path {
            // Senza una nota, il percorso aiuta il modello a capire (es. "CoreSuggestions").
            prompt += "\nPercorso (solo per capire, non citarlo): \(path)"
        }
        prompt += """


        Spiega in 2 o 3 frasi semplici a cosa serve questo processo.
        Usa l'informazione sicura se c'è; altrimenti deducilo dal nome e, se non sei sicuro, dillo.
        Non dire se si può chiudere: lo mostra già l'app. Non fare elenchi.
        """
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }

    /// Messaggio quando il processo non è in esecuzione.
    public static func notFoundMessage(for name: String) -> String {
        // Alcuni processi (es. kernel_task) sono sempre attivi ma non leggibili
        // senza permessi di amministratore: non diciamo "non è attivo".
        if let note = KnownProcesses.note(for: name) {
            return "«\(name)» fa parte di macOS: \(note). Non chiuderlo."
        }
        return "Non trovo «\(name)» tra i processi attivi. Controlla il nome: puoi copiarlo da Monitoraggio Attività."
    }
}
