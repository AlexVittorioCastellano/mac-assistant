import Foundation

/// Un problema (o una conferma) individuato nei dati, in parole semplici.
public struct Finding: Sendable, Equatable, Identifiable {
    public enum Severity: Int, Sendable, Comparable {
        case ok, info, warning, critical
        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String
    public var severity: Severity
    public var title: String
    /// Cosa può fare l'utente. Scritto dal codice, non dall'AI:
    /// così i consigli sono sempre corretti e sicuri.
    public var advice: String?

    public init(id: String, severity: Severity, title: String, advice: String? = nil) {
        self.id = id
        self.severity = severity
        self.title = title
        self.advice = advice
    }
}

/// Funzione 1: "Perché il Mac è lento?"
///
/// Due fasi:
/// 1. Regole deterministiche (`findings`): veloci, precise, sempre disponibili,
///    anche senza AI.
/// 2. L'AI riceve dati e regole e li spiega in italiano semplice.
///    Numeri e consigli li produce il codice, non il modello: così non può
///    inventarli né suggerire azioni pericolose (es. chiudere processi di macOS).
public enum SlowMacDiagnosis {

    // MARK: Fase 1: regole

    /// I consigli pratici, senza ripetizioni, nell'ordine dei problemi.
    public static func advice(from findings: [Finding]) -> [String] {
        var seen = Set<String>()
        return findings.compactMap(\.advice).filter { seen.insert($0).inserted }
    }

    public static func findings(for s: SystemSnapshot) -> [Finding] {
        var result: [Finding] = []

        if s.cpuUsagePercent >= 85 {
            result.append(.init(id: "cpu", severity: .critical,
                                title: "Il processore è al limite (\(Fmt.percent(s.cpuUsagePercent)))"))
        } else if s.cpuUsagePercent >= 60 {
            result.append(.init(id: "cpu", severity: .warning,
                                title: "Il processore è molto impegnato (\(Fmt.percent(s.cpuUsagePercent)))"))
        }

        // `ps` misura in percentuale di un singolo core: 80 = quasi un core intero.
        // Un processo può occupare un core intero senza rallentare tutto il Mac
        // (se ci sono altri core liberi): lo segnaliamo come avviso solo se
        // anche il Mac nel complesso è carico.
        if let top = s.topByCPU(1).first, top.cpuPercent >= 80, s.cpuUsagePercent < 40 {
            result.append(.init(id: "topcpu", severity: .info,
                                title: "«\(top.name)» lavora molto, ma il Mac ha ancora potenza libera"))
        } else if let top = s.topByCPU(1).first, top.cpuPercent >= 80 {
            if isSystem(top) {
                result.append(.init(id: "topcpu", severity: .warning,
                                    title: "macOS sta facendo un lavoro in background («\(top.name)»)",
                                    advice: "Aspetta qualche minuto: di solito finisce da solo. Se dura per ore, riavvia il Mac."))
            } else {
                result.append(.init(id: "topcpu", severity: .warning,
                                    title: "«\(top.name)» sta usando molto il processore",
                                    advice: "Se in questo momento non ti serve, chiudi «\(top.name)» (salva prima il lavoro)."))
            }
        }

        switch s.memory.pressure {
        case .critical:
            result.append(.init(id: "mem", severity: .critical, title: "La memoria è esaurita",
                                advice: "Chiudi le app e le schede del browser che non stai usando."))
        case .warning:
            result.append(.init(id: "mem", severity: .warning, title: "La memoria è quasi piena",
                                advice: "Chiudi le app e le schede del browser che non stai usando."))
        case .normal:
            break
        }

        if s.memory.swapUsedBytes >= 2 * 1_073_741_824 {
            result.append(.init(id: "swap", severity: .warning,
                                title: "Il Mac usa il disco come memoria extra (\(Fmt.gb(s.memory.swapUsedBytes)))",
                                advice: "Quando puoi, riavvia il Mac: libera la memoria."))
        }

        if let top = s.topByMemory(1).first, s.memory.totalBytes > 0,
           Double(top.residentBytes) / Double(s.memory.totalBytes) >= 0.25 {
            result.append(.init(id: "topmem", severity: .info,
                                title: "«\(top.name)» occupa molta memoria (\(Fmt.gb(top.residentBytes)))",
                                advice: isSystem(top) ? nil : "Se non ti serve, chiudi «\(top.name)» per liberare memoria."))
        }

        switch s.thermal {
        case .critical:
            result.append(.init(id: "heat", severity: .critical, title: "Il Mac è molto caldo e si sta rallentando per protezione",
                                advice: "Appoggia il Mac su una superficie rigida e lascia libere le prese d'aria."))
        case .serious:
            result.append(.init(id: "heat", severity: .warning, title: "Il Mac è caldo e potrebbe rallentare per raffreddarsi",
                                advice: "Appoggia il Mac su una superficie rigida e lascia libere le prese d'aria."))
        default:
            break
        }

        let days = Fmt.days(s.uptime)
        if days >= 14 {
            result.append(.init(id: "uptime", severity: .info, title: "Il Mac non viene riavviato da \(days) giorni",
                                advice: "Riavvia il Mac: spesso basta per tornare veloce."))
        }

        if result.isEmpty {
            result.append(.init(id: "ok", severity: .ok, title: "Nessun problema evidente in questo momento"))
        }
        return result.sorted { $0.severity > $1.severity }
    }

    /// Processo di macOS (non va chiuso): utente di sistema o processo noto.
    static func isSystem(_ p: ProcessGroup) -> Bool {
        p.isSystem || KnownProcesses.notes[p.name] != nil
    }

    // MARK: Fase 2: richiesta all'AI

    static let instructions = """
    Sei un assistente che aiuta persone non esperte a capire il proprio Mac.
    Rispondi sempre in italiano, con frasi brevi, chiare e senza gergo tecnico.
    Basati solo sui dati forniti: non inventare numeri, programmi o cause.
    Non dire mai di aver chiuso programmi o cambiato impostazioni: puoi solo dare consigli.
    Le attività di macOS in background fanno parte del sistema: non suggerire mai di chiuderle.
    """

    public static func request(question: String, snapshot s: SystemSnapshot, findings: [Finding]) -> AIRequest {
        // App dell'utente e attività di macOS sono elencate separatamente:
        // il modello può suggerire di chiudere solo le prime.
        let byCPU = s.topByCPU(8), byMem = s.topByMemory(8)
        func list(_ items: [ProcessGroup], system: Bool, _ value: (ProcessGroup) -> String) -> String {
            // Solo processi che pesano davvero (≥ 10% di un core o ≥ 0,5 GB).
            let chosen = items.filter { isSystem($0) == system && ($0.cpuPercent >= 10 || $0.residentBytes >= 512 << 20) }.prefix(3)
            return chosen.isEmpty ? "nessuna" : chosen.map { "\($0.name) \(value($0))" }.joined(separator: ", ")
        }
        let cpu: (ProcessGroup) -> String = { Fmt.percent($0.cpuPercent) }
        let mem: (ProcessGroup) -> String = { Fmt.gb($0.residentBytes) }

        let pressure = switch s.memory.pressure {
            case .normal: "normale"
            case .warning: "alta"
            case .critical: "critica"
        }
        let thermal = switch s.thermal {
            case .nominal, .fair: "normale"
            case .serious: "alta"
            case .critical: "molto alta"
        }

        // Note solo per i processi che compaiono davvero nei dati.
        let shown = Set(byCPU.filter { isSystem($0) && $0.cpuPercent >= 10 }.prefix(3).map(\.name))
        let notes = shown.sorted().compactMap { name in
            KnownProcesses.notes[name].map { "- \(name): \($0)" }
        }

        // Nessun problema: niente elenchi di processi (il modello tenderebbe a
        // presentarli come problemi), solo una rassicurazione.
        if findings.allSatisfy({ $0.severity == .ok }) {
            let prompt = """
            Domanda dell'utente: \(question)

            L'app ha controllato il Mac e non ha trovato problemi: processore al \(Fmt.percent(s.cpuUsagePercent)), \
            memoria con pressione \(pressure), temperatura \(thermal).

            Rassicura l'utente in 2 frasi semplici. Spiega che se il Mac era lento poco fa, \
            potrebbe essere stato un rallentamento momentaneo ormai passato.
            """
            return AIRequest(instructions: instructions, prompt: prompt)
        }

        // Il modello è piccolo: prima i problemi già individuati (la parte
        // importante), poi solo i dati essenziali, senza processi irrilevanti.
        var prompt = """
        Domanda dell'utente: \(question)

        Problemi individuati dall'app (sono la causa da spiegare):
        \(findings.map { "- \($0.title)" }.joined(separator: "\n"))

        Dati misurati adesso sul Mac:
        - Processore: \(Fmt.percent(s.cpuUsagePercent)) in uso in totale
        - Memoria: \(Fmt.gb(s.memory.usedBytes)) usati su \(Fmt.gb(s.memory.totalBytes)); pressione \(pressure)
        - Temperatura: \(thermal)
        - App aperte che usano più processore: \(list(byCPU, system: false, cpu))
        - App aperte che usano più memoria: \(list(byMem, system: false, mem))
        - Attività di macOS (non vanno chiuse): \(list(byCPU, system: true, cpu))
        """
        if !notes.isEmpty {
            prompt += "\n\nCosa sono alcune attività di macOS:\n" + notes.joined(separator: "\n")
        }
        prompt += """


        Spiega in 2 o 3 frasi semplici cosa sta succedendo, partendo dai problemi individuati.
        Parla solo dei programmi nominati sopra. Se non ci sono problemi, rassicura l'utente.
        Non dare consigli e non fare elenchi: i consigli li mostra già l'app.
        """
        return AIRequest(instructions: instructions, prompt: prompt)
    }
}
