import Foundation

/// Funzione "Caccia alle app sospette": programmi che partono da soli e app
/// installate, controllati con la firma digitale e con regole semplici.
///
/// Tutto deciso dal codice (niente AI) e in sola lettura: l'app spiega cosa
/// ha trovato e come toglierlo, ma non elimina nulla.
public enum SecurityScan {

    /// Software noto come indesiderato (finti "pulitori", adware…).
    /// Nomi in minuscolo; si cercano nel nome dell'app o del programma.
    static let knownUnwanted = [
        "mackeeper", "advanced mac cleaner", "advancedmaccleaner", "mac auto fixer", "macautofixer",
        "mac cleanup pro", "maccleanuppro", "smart mac booster", "mac tonic", "mactonic",
        "search baron", "searchbaron", "search marquis", "searchmarquis", "shlayer", "pirrit",
        "genieo", "vsearch", "bundlore", "adload", "mughthesec",
    ]

    /// Programmi che eseguono comandi o script (spesso usati dagli adware).
    static let scriptRunners: Set<String> = ["bash", "sh", "zsh", "python", "python3", "osascript", "curl", "perl", "ruby", "node"]

    /// Cartelle dove un programma serio non si installa.
    static let oddLocations = ["/tmp/", "/private/tmp/", "/Users/Shared/", "/private/var/folders/", "/var/folders/"]

    static func isKnownUnwanted(_ text: String) -> Bool {
        let t = text.lowercased()
        return knownUnwanted.contains { t.contains($0) }
    }

    public struct Verdict: Sendable, Equatable {
        public var severity: Finding.Severity
        public var title: String
        public var advice: String?
    }

    /// Una firma rotta non prova cattive intenzioni: lo diciamo con onestà.
    static let brokenExplanation = "Succede quando un file viene cambiato dopo la firma: a volte è innocuo (app create da altri programmi, come gli strumenti per sviluppatori), a volte no."

    static let removeBackground = "Puoi disattivarlo in Impostazioni di Sistema → Generali → Elementi login ed estensioni (sezione «Consenti in background»). Se viene da un'app che non usi, disinstalla l'app."

    /// Verdetto su un programma in background.
    public static func verdict(for item: BackgroundItem, trust: CodeTrust) -> Verdict {
        let program = item.executable ?? ""
        let name = displayName(item)
        let isApple = item.label.hasPrefix("com.apple.") && trust == .apple

        if isKnownUnwanted(item.label) || isKnownUnwanted(program) {
            return Verdict(severity: .critical, title: "«\(name)» è un software noto come indesiderato",
                           advice: "È un programma che mostra pubblicità o finti allarmi. " + removeBackground)
        }
        if trust == .broken {
            return Verdict(severity: .warning, title: "«\(name)» ha una firma digitale che non corrisponde più al programma",
                           advice: brokenExplanation + " Se non lo riconosci: " + removeBackground)
        }
        let base = URL(fileURLWithPath: program).lastPathComponent
        if !isApple, scriptRunners.contains(base), item.arguments.count > 1 {
            return Verdict(severity: .warning, title: "«\(name)» parte da solo ed esegue uno script",
                           advice: "Gli script avviati in background sono un trucco usato dagli adware. Se non sai cos'è: " + removeBackground)
        }
        if oddLocations.contains(where: program.hasPrefix) || URL(fileURLWithPath: program).lastPathComponent.hasPrefix(".") {
            return Verdict(severity: .warning, title: "«\(name)» parte da solo da una cartella nascosta o temporanea",
                           advice: "I programmi seri non si installano lì. " + removeBackground)
        }
        switch trust {
        case .missing:
            return Verdict(severity: .info, title: "«\(name)» punta a un programma che non esiste più",
                           advice: "È un resto di un'app disinstallata: non fa danni, ma puoi toglierlo. " + removeBackground)
        case .unsigned, .unverified:
            return Verdict(severity: .warning, title: "«\(name)» parte da solo e nessuno sviluppatore verificato lo firma",
                           advice: "Se non sai da dove viene: " + removeBackground)
        case .apple:
            return Verdict(severity: .ok, title: "«\(name)» (di Apple)", advice: nil)
        case .appStore:
            return Verdict(severity: .ok, title: "«\(name)» (dall'App Store)", advice: nil)
        case .identifiedDeveloper(let dev):
            return Verdict(severity: .ok, title: "«\(name)» di \(dev)", advice: nil)
        case .broken:
            return Verdict(severity: .critical, title: "«\(name)»", advice: nil)  // gestito sopra
        }
    }

    /// Verdetto su un'app installata (`nil` = tutto a posto, non serve mostrarla).
    public static func verdict(for app: InstalledApp) -> Verdict? {
        if isKnownUnwanted(app.name) {
            return Verdict(severity: .critical, title: "«\(app.name)» è un software noto come indesiderato",
                           advice: "Mostra finti allarmi per farti pagare. Disinstallala: trascinala dalla cartella Applicazioni al Cestino e svuotalo.")
        }
        switch app.trust {
        case .broken:
            return Verdict(severity: .warning, title: "«\(app.name)» ha una firma digitale che non corrisponde più all'app",
                           advice: brokenExplanation + " Se non la riconosci, eliminala; se ti serve, scaricala di nuovo dal sito ufficiale.")
        case .unsigned, .unverified:
            return Verdict(severity: .warning, title: "«\(app.name)» non è firmata da uno sviluppatore verificato",
                           advice: "Se l'hai scaricata tu da un sito ufficiale (alcuni programmi gratuiti non sono firmati), va bene. Se non sai da dove viene, eliminala.")
        default:
            return nil
        }
    }

    /// Nome leggibile: dal programma, altrimenti dall'etichetta.
    static func displayName(_ item: BackgroundItem) -> String {
        if let exe = item.executable, !exe.isEmpty {
            // Se sta dentro un'app, il nome dell'app è più chiaro.
            if let app = ProcessKind.outermostAppBundlePath(in: exe) {
                return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            }
            return URL(fileURLWithPath: exe).lastPathComponent
        }
        return item.label
    }

    // MARK: Cosa mostrare

    public static func findings(for result: SecurityScanner.Result) -> [Finding] {
        var rows: [Finding] = []
        for (i, entry) in result.items.enumerated() {
            let (item, trust) = entry
            // Gli elementi di Apple sono parte di macOS: non li elenchiamo.
            if item.label.hasPrefix("com.apple.") && trust == .apple { continue }
            let v = verdict(for: item, trust: trust)
            let icon = item.executable.flatMap(ProcessKind.outermostAppBundlePath(in:))
            rows.append(Finding(id: "bg\(i)", severity: v.severity, title: v.title, advice: v.advice,
                                iconPath: icon, symbol: v.severity >= .warning ? "exclamationmark.shield.fill" : "gearshape.2"))
        }
        let appProblems = result.apps.compactMap { app in verdict(for: app).map { (app, $0) } }
        for (app, v) in appProblems {
            rows.append(Finding(id: "app:\(app.path)", severity: v.severity, title: v.title, advice: v.advice,
                                iconPath: app.path))
        }

        // Problemi prima (ordine stabile).
        let sorted = rows.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
        let problems = rows.filter { $0.severity >= .warning }.count
        let worst = rows.map(\.severity).max() ?? .ok

        let headline = Finding(
            id: "overall", severity: problems == 0 ? .ok : worst,
            title: problems == 0 ? "Nessuna app sospetta"
                : problems == 1 ? "C'è 1 cosa da controllare" : "Ci sono \(problems) cose da controllare",
            symbol: problems == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")

        var summary: [Finding] = []
        let background = rows.filter { $0.id.hasPrefix("bg") }.count
        summary.append(Finding(id: "bgcount", severity: .info,
                               title: background == 0 ? "Nessun programma di altre aziende parte da solo in background"
                                   : "Programmi che partono da soli in background: \(background)",
                               symbol: "gearshape.2"))
        if !result.apps.isEmpty {
            let ok = result.apps.count - appProblems.count
            summary.append(Finding(id: "appcount", severity: .info,
                                   title: "App controllate: \(result.apps.count), firmate da sviluppatori verificati: \(ok)",
                                   symbol: "app.badge.checkmark"))
        }
        return [headline] + sorted + summary
    }

    /// Quante cose sospette (per il controllo generale).
    public static func problemCount(_ result: SecurityScanner.Result) -> Int {
        findings(for: result).filter { $0.id != "overall" && $0.severity >= .warning }.count
    }
}
