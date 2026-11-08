import Foundation

/// Un avviso da mostrare all'utente (notifica + banner nel riquadro).
public struct MacAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case cpuHog, memory, heat, disk }

    /// Stabile per lo stesso problema (es. "cpuHog:Spotify"): serve a non ripeterlo.
    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String
    /// La domanda da fare se l'utente preme "Vedi".
    public var question: String
}

/// Funzione "Avvisi prima che sia tardi".
///
/// Riceve una misura al minuto e decide quando avvisare. È una macchina a
/// stati pura (nessun timer, nessuna notifica): così si può testare il
/// passare del tempo senza aspettare. Regole pensate per NON disturbare:
/// - si avvisa solo per problemi che DURANO (non per un picco di pochi secondi);
/// - lo stesso avviso non si ripete prima di `repeatAfter`.
public struct AlertMonitor: Sendable {
    public struct Rules: Sendable {
        /// Un'app che usa almeno questo processore (100 = un core intero)…
        public var cpuThreshold: Double = 80
        /// …per almeno questo tempo.
        public var cpuDuration: TimeInterval = 10 * 60
        public var memoryDuration: TimeInterval = 5 * 60
        public var heatDuration: TimeInterval = 5 * 60
        /// Spazio libero sotto cui avvisare (in proporzione e in assoluto).
        public var diskFreeRatio: Double = 0.10
        public var diskFreeBytes: UInt64 = 10 * 1_073_741_824
        /// Tempo minimo prima di ripetere lo stesso avviso.
        public var repeatAfter: TimeInterval = 6 * 3600
        public init() {}
    }

    public var rules = Rules()
    /// Da quando dura ogni condizione (chiave = id dell'avviso).
    private var since: [String: Date] = [:]
    /// Quando è stato mandato l'ultimo avviso per ogni id.
    private var lastSent: [String: Date] = [:]
    /// Avvisi la cui condizione è ancora vera (per il banner e l'icona).
    public private(set) var active: [MacAlert] = []

    public init(rules: Rules = Rules()) { self.rules = rules }

    /// Una misura. Restituisce gli avvisi NUOVI da notificare adesso.
    public mutating func update(snapshot s: SystemSnapshot, diskFree: UInt64, diskTotal: UInt64,
                                now: Date = Date()) -> [MacAlert] {
        var current: [MacAlert] = []   // condizioni vere e durate abbastanza
        var seen = Set<String>()       // condizioni vere adesso (anche se non ancora durate)

        /// Da quanto dura una condizione, in parole ("da 25 minuti").
        func elapsed(_ id: String) -> String {
            let minutes = Int(now.timeIntervalSince(since[id] ?? now) / 60)
            switch minutes {
            case ..<2: return L.t("alert.elapsed.few")
            case ..<60: return L.t("alert.elapsed.minutes", minutes)
            case ..<120: return L.t("alert.elapsed.hour")
            default: return L.t("alert.elapsed.hours", minutes / 60)
            }
        }

        func check(_ makeAlert: () -> MacAlert, id: String, isTrue: Bool, duration: TimeInterval) {
            guard isTrue else { return }
            seen.insert(id)
            let start = since[id] ?? now
            since[id] = start
            if now.timeIntervalSince(start) >= duration { current.append(makeAlert()) }
        }

        // App dell'utente che occupa il processore a lungo (mai processi di macOS).
        for p in s.processes where !p.isSystem && p.cpuPercent >= rules.cpuThreshold {
            let id = "cpuHog:\(p.name)"
            check({ MacAlert(id: id, kind: .cpuHog,
                             title: L.t("alert.cpu.title", p.name, elapsed(id)),
                             body: L.t("alert.cpu.body"),
                             question: L.t("question.processNamed", p.name)) },
                  id: id, isTrue: true, duration: rules.cpuDuration)
        }

        check({ MacAlert(id: "memory", kind: .memory, title: L.t("alert.memory.title", elapsed("memory")),
                         body: L.t("alert.memory.body"),
                         question: Assistant.slowMacQuestion) },
              id: "memory", isTrue: s.memory.pressure == .critical, duration: rules.memoryDuration)

        check({ MacAlert(id: "heat", kind: .heat, title: L.t("alert.heat.title", elapsed("heat")),
                         body: L.t("alert.heat.body"),
                         question: Assistant.slowMacQuestion) },
              id: "heat", isTrue: s.thermal == .serious || s.thermal == .critical, duration: rules.heatDuration)

        let lowDisk = diskTotal > 0 && (Double(diskFree) / Double(diskTotal) < rules.diskFreeRatio
                                        || diskFree < rules.diskFreeBytes)
        check({ MacAlert(id: "disk", kind: .disk, title: L.t("alert.disk.title"),
                         body: L.t("alert.disk.body", Fmt.size(diskFree)),
                         question: Assistant.diskQuestion) },
              id: "disk", isTrue: lowDisk, duration: 0)

        // Le condizioni finite si dimenticano: se tornano, il conteggio riparte.
        since = since.filter { seen.contains($0.key) }
        active = current

        let fresh = current.filter { a in
            guard let last = lastSent[a.id] else { return true }
            return now.timeIntervalSince(last) >= rules.repeatAfter
        }
        for a in fresh { lastSent[a.id] = now }
        return fresh
    }
}
