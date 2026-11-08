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
        /// `false` se trovato solo per nome parziale (es. "AirDrop" dentro
        /// "AirDropHandoffIntentsExtension"): potrebbe non essere quello cercato.
        public var isExactMatch = true
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
        var exact = true
        if matching.isEmpty {
            let partial = samples.filter { $0.name.localizedCaseInsensitiveContains(name) }
            if Set(partial.map { ProcessLister.logicalName($0.name) }).count == 1 { matching = partial; exact = false }
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
        return Details(group: group, note: KnownProcesses.note(for: main.name), isExactMatch: exact)
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

    /// Simbolo per i processi senza un'app da cui prendere l'icona.
    public static func symbol(for g: ProcessGroup) -> String {
        g.isSystem ? "gearshape.fill" : "app.dashed"
    }

    public static func findings(for d: Details) -> [Finding] {
        let g = d.group
        var result: [Finding] = []
        // L'icona del processo accompagna la riga "che tipo è".
        let icon = ProcessKind.outermostAppBundlePath(in: g.path)
        let symbol = symbol(for: g)

        switch g.kind {
        case .macOS:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.macos"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .critical, title: L.t("process.close.macos"),
                                advice: g.cpuPercent >= 50
                                    ? L.t("process.close.macos.advice")
                                    : nil))
        case .app(let name):
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.app", name),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .ok, title: L.t("process.close.app"),
                                advice: L.t("process.close.app.advice")))
        case .appComponent(let app):
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.component", app),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .info, title: L.t("process.close.component", app),
                                advice: L.t("process.close.component.advice", app)))
        case .background:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.background"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .warning, title: L.t("process.close.background"),
                                advice: L.t("process.close.background.advice")))
        case .unknown:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.unknown"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .warning, title: L.t("process.close.unknown")))
        }

        var usage = L.t("process.usage", Fmt.percent(g.cpuPercent), Fmt.size(g.residentBytes))
        if g.instanceCount > 1 { usage += L.t("process.usage.copies", g.instanceCount) }
        result.append(.init(id: "usage", severity: .info, title: usage))
        return result
    }

    // MARK: Richiesta all'AI

    public static func request(question: String, details d: Details) -> AIRequest {
        let g = d.group
        let kind = switch g.kind {
            case .macOS: L.t("process.prompt.kind.macos")
            case .app(let name): L.t("process.prompt.kind.app", name)
            case .appComponent(let app): L.t("process.prompt.kind.component", app)
            case .background: L.t("process.prompt.kind.background")
            case .unknown: L.t("process.prompt.kind.unknown")
        }
        let verdict = findings(for: d).first { $0.id == "close" }?.title ?? ""

        var prompt = L.t("process.prompt", question, g.name, kind, verdict)
        if let note = d.note {
            prompt += "\n" + L.t("process.prompt.note", note)
        } else if let path = g.path {
            // Senza una nota, il percorso aiuta il modello a capire (es. "CoreSuggestions").
            prompt += "\n" + L.t("process.prompt.path", path)
        }
        prompt += "\n\n" + L.t("process.prompt.end")
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }

    /// Messaggio quando il processo non è in esecuzione.
    public static func notFoundMessage(for name: String) -> String {
        // Alcuni processi (es. kernel_task) sono sempre attivi ma non leggibili
        // senza permessi di amministratore: non diciamo "non è attivo".
        if let note = KnownProcesses.note(for: name) {
            return L.t("process.notfound.known", name, note)
        }
        return L.t("process.notfound", name)
    }
}
