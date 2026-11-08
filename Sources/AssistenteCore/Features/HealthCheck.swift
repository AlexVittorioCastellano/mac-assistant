import Foundation

/// Funzione "Controlla il mio Mac": un semaforo con tutte le cose importanti
/// (velocità, spazio, backup, sicurezza, aggiornamenti, batteria).
///
/// Tutto deciso dal codice, niente AI: le voci si capiscono da sole e la
/// risposta è immediata. L'app non cambia nessuna impostazione: dice solo
/// cosa sistemare e dove.
public enum HealthCheck {

    public struct Input: Sendable {
        public var snapshot: SystemSnapshot
        public var disk: (total: UInt64, free: UInt64)
        public var status: MacStatus
        /// Cose sospette trovate dalla caccia alle app (`nil` = non controllato).
        public var suspicious: Int?
        public var now: Date

        public init(snapshot: SystemSnapshot, disk: (total: UInt64, free: UInt64), status: MacStatus,
                    suspicious: Int? = nil, now: Date = Date()) {
            self.snapshot = snapshot
            self.disk = disk
            self.status = status
            self.suspicious = suspicious
            self.now = now
        }
    }

    public static func findings(for input: Input) -> [Finding] {
        let items = checks(input)
        // Problemi prima, poi le informazioni, poi ciò che va bene. A parità di
        // gravità resta l'ordine fisso delle voci, così l'elenco non "balla".
        let sorted = items.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
        let problems = items.filter { $0.severity >= .warning }.count
        return [headline(problems: problems, worst: items.map(\.severity).max() ?? .ok)] + sorted
    }

    static func headline(problems: Int, worst: Finding.Severity) -> Finding {
        let title = switch problems {
            case 0: "Il tuo Mac sta bene"
            case 1: "C'è 1 cosa da sistemare"
            default: "Ci sono \(problems) cose da sistemare"
        }
        let symbol = problems == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        return Finding(id: "overall", severity: problems == 0 ? .ok : worst, title: title, symbol: symbol)
    }

    static func checks(_ input: Input) -> [Finding] {
        var result: [Finding] = []
        let s = input.status

        // Velocità: riusa le regole di "Mac lento" (senza il riavvio, che è a parte).
        let slow = SlowMacDiagnosis.findings(for: input.snapshot).filter { $0.id != "uptime" && $0.id != "ok" }
        if let worst = slow.max(by: { $0.severity < $1.severity }), worst.severity >= .warning {
            result.append(.init(id: "speed", severity: .warning, title: "Il Mac è sotto sforzo: \(worst.title.lowercasedFirst)",
                                advice: "Premi «Mac lento» per vedere cosa lo rallenta.", symbol: "speedometer"))
        } else {
            result.append(.init(id: "speed", severity: .ok, title: "Il Mac non è sotto sforzo", symbol: "speedometer"))
        }

        // Spazio
        let usage = DiskUsage(totalBytes: input.disk.total, freeBytes: input.disk.free, purgeableBytes: 0,
                              macOSBytes: 0, items: [], localSnapshotCount: 0)
        switch DiskSpaceAnalysis.level(usage) {
        case .ok:
            result.append(.init(id: "disk", severity: .ok, title: "Spazio libero: \(Fmt.size(input.disk.free))", symbol: "internaldrive"))
        case let level:
            result.append(.init(id: "disk", severity: level, title: "Lo spazio sta finendo: \(Fmt.size(input.disk.free)) liberi",
                                advice: "Premi «Spazio disco» per vedere cosa occupa più spazio.", symbol: "internaldrive"))
        }

        // Backup
        switch s.backup {
        case .notConfigured:
            result.append(.init(id: "backup", severity: .warning, title: "Nessun backup configurato",
                                advice: "Collega un disco esterno e attiva Time Machine in Impostazioni di Sistema → Generali → Time Machine: se il Mac si rompe, non perdi i tuoi file.",
                                symbol: "clock.arrow.circlepath"))
        case .configured(let last?):
            let days = Int(input.now.timeIntervalSince(last) / 86_400)
            if days > 7 {
                result.append(.init(id: "backup", severity: .warning, title: "Ultimo backup \(days) giorni fa",
                                    advice: "Collega il disco di Time Machine per fare un backup aggiornato.",
                                    symbol: "clock.arrow.circlepath"))
            } else {
                let when = days == 0 ? "oggi" : days == 1 ? "ieri" : "\(days) giorni fa"
                result.append(.init(id: "backup", severity: .ok, title: "Ultimo backup: \(when)", symbol: "clock.arrow.circlepath"))
            }
        case .configured(nil):
            result.append(.init(id: "backup", severity: .ok, title: "Time Machine è configurato", symbol: "clock.arrow.circlepath"))
        case .unknown:
            break
        }

        // Sicurezza
        if let on = s.fileVaultOn {
            result.append(on
                ? .init(id: "filevault", severity: .ok, title: "Il disco è cifrato (FileVault)", symbol: "lock.fill")
                : .init(id: "filevault", severity: .warning, title: "Il disco non è cifrato",
                        advice: "Attiva FileVault in Impostazioni di Sistema → Privacy e sicurezza: se perdi il Mac, nessuno potrà leggere i tuoi file.",
                        symbol: "lock.open.fill"))
        }
        if s.gatekeeperOn == false {
            result.append(.init(id: "gatekeeper", severity: .critical,
                                title: "Il controllo di sicurezza delle app scaricate (Gatekeeper) è disattivato",
                                advice: "Gatekeeper si può riattivare solo con un comando nel Terminale: se non l'hai disattivato tu, fatti aiutare da un tecnico.",
                                symbol: "shield.slash.fill"))
        } else if s.gatekeeperOn == true {
            result.append(.init(id: "gatekeeper", severity: .ok, title: "Le app scaricate vengono controllate (Gatekeeper)", symbol: "checkmark.shield.fill"))
        }
        if s.sipOn == false {
            result.append(.init(id: "sip", severity: .critical,
                                title: "La protezione dei file di sistema (SIP) è disattivata",
                                advice: "SIP si riattiva solo dalla modalità di ripristino del Mac: se non l'hai disattivata tu, fatti aiutare da un tecnico.",
                                symbol: "shield.slash.fill"))
        } else if s.sipOn == true {
            result.append(.init(id: "sip", severity: .ok, title: "I file di sistema sono protetti (SIP)", symbol: "checkmark.shield.fill"))
        }
        if s.firewallOn == false {
            // Apple lo spedisce spento: è un'informazione, non un problema.
            result.append(.init(id: "firewall", severity: .info, title: "Il firewall è spento (impostazione iniziale di macOS)",
                                advice: "Se usi spesso reti Wi‑Fi pubbliche, puoi accenderlo in Impostazioni di Sistema → Rete → Firewall.",
                                symbol: "flame"))
        } else if s.firewallOn == true {
            result.append(.init(id: "firewall", severity: .ok, title: "Il firewall è acceso", symbol: "flame"))
        }

        // App sospette
        if let n = input.suspicious {
            result.append(n == 0
                ? .init(id: "apps", severity: .ok, title: "Nessuna app sospetta", symbol: "checkmark.shield.fill")
                : .init(id: "apps", severity: .warning,
                        title: n == 1 ? "C'è 1 app o programma da controllare" : "Ci sono \(n) app o programmi da controllare",
                        advice: "Premi «App sospette» per vedere cosa sono e come toglierli.",
                        symbol: "exclamationmark.shield.fill"))
        }

        // Aggiornamenti
        if let pending = s.pendingUpdates, pending > 0 {
            result.append(.init(id: "updates", severity: .warning,
                                title: pending == 1 ? "C'è 1 aggiornamento da installare" : "Ci sono \(pending) aggiornamenti da installare",
                                advice: "Installa gli aggiornamenti in Impostazioni di Sistema → Generali → Aggiornamento Software: correggono problemi di sicurezza.",
                                symbol: "arrow.down.circle"))
        } else if s.automaticUpdatesOn == false {
            result.append(.init(id: "updates", severity: .warning, title: "Gli aggiornamenti automatici sono spenti",
                                advice: "Attivali in Impostazioni di Sistema → Generali → Aggiornamento Software → Aggiornamenti automatici.",
                                symbol: "arrow.down.circle"))
        } else if s.automaticUpdatesOn == true {
            result.append(.init(id: "updates", severity: .ok, title: "Gli aggiornamenti automatici sono attivi", symbol: "arrow.down.circle"))
        }

        // Batteria
        if let b = s.battery {
            if b.healthPercent < 80 {
                result.append(.init(id: "battery", severity: .warning,
                                    title: "La batteria è consumata (\(b.healthPercent)% della capacità iniziale)",
                                    advice: "Sotto l'80% Apple consiglia di farla controllare in assistenza.",
                                    symbol: "battery.25percent"))
            } else {
                result.append(.init(id: "battery", severity: .ok,
                                    title: "Batteria in salute (\(b.healthPercent)%, \(b.cycleCount) cicli)", symbol: "battery.100percent"))
            }
        }

        // Riavvio
        let days = Fmt.days(input.snapshot.uptime)
        if days >= 14 {
            result.append(.init(id: "uptime", severity: .info, title: "Non riavvii il Mac da \(days) giorni",
                                advice: "Riavvia il Mac ogni tanto: installa gli aggiornamenti e libera la memoria.",
                                symbol: "arrow.clockwise"))
        }
        return result
    }
}

extension String {
    /// "Il processore…" -> "il processore…"
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
