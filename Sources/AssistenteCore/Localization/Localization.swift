import Foundation

/// Un pacchetto lingua: tutti i testi e le regole che dipendono dalla lingua.
/// Un file JSON per lingua in `Sources/AssistenteCore/Languages/` (es. it.json).
/// Per aggiungere una lingua: copia en.json, traducilo e aggiungi i casi in Evals/.
public struct LanguagePack: Decodable, Sendable {
    public struct Router: Decodable, Sendable {
        var slow: [String]
        var strongSlow: [String]
        var disk: [String]
        var health: [String]
        var security: [String]
        var cleanup: [String]
        var processTriggers: [String]
        var fillerWords: [String]
        var howTo: [String]
        var followUp: [String]
    }

    public struct Guide: Decodable, Sendable {
        var keywords: [String]
        var text: String
    }

    public struct Message: Decodable, Sendable {
        var id: String
        var patterns: [String]
        var title: String
        var advice: String
    }

    /// Codice della lingua ("it", "en").
    public var code: String
    /// Nome della lingua nella lingua stessa ("Italiano", "English").
    public var name: String
    /// Locale per numeri, voce, testo (es. "it_IT").
    public var locale: String
    var strings: [String: String]
    var router: Router
    var guides: [Guide]
    var processes: [String: String]
    var messages: [Message]

    public var foundationLocale: Locale { Locale(identifier: locale) }
}

/// Accesso ai testi nella lingua corrente: `L.t("chiave", argomenti…)`.
///
/// Lingua corrente, in ordine: quella del task (per i test, che così possono
/// girare in parallelo in lingue diverse), quella scelta nelle impostazioni,
/// quella del Mac, l'inglese.
public enum L {
    /// Lingua di riserva quando quella del Mac non è disponibile.
    public static let fallbackCode = "en"

    @TaskLocal public static var taskLanguage: String?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _override: String?

    /// Lingua scelta dall'utente nelle impostazioni (`nil` = automatica).
    public static var override: String? {
        // ASSISTENTE_LINGUA (es. "it") fissa la lingua: la usano i test, così
        // girano uguali su qualunque Mac, e chi vuole provare un'altra lingua.
        get { lock.withLock { _override } ?? ProcessInfo.processInfo.environment["ASSISTENTE_LINGUA"] }
        set { lock.withLock { _override = newValue } }
    }

    /// Tutti i pacchetti disponibili, per codice.
    public static let packs: [String: LanguagePack] = loadPacks()

    public static var available: [LanguagePack] {
        packs.values.sorted { $0.name < $1.name }
    }

    /// La lingua del Mac, se c'è un pacchetto per lei.
    public static var systemLanguageCode: String {
        for identifier in Locale.preferredLanguages {
            let code = String(identifier.prefix(2))
            if packs[code] != nil { return code }
        }
        return fallbackCode
    }

    public static var current: LanguagePack {
        let code = taskLanguage ?? override ?? systemLanguageCode
        return packs[code] ?? packs[fallbackCode] ?? packs.values.first!
    }

    public static var locale: Locale { current.foundationLocale }

    /// Testo tradotto. `{0}`, `{1}`… vengono sostituiti dagli argomenti.
    /// Se manca nella lingua corrente si usa l'inglese, poi la chiave stessa
    /// (così un testo mancante si nota, ma l'app non si rompe).
    public static func t(_ key: String, _ args: Any...) -> String {
        var text = current.strings[key] ?? packs[fallbackCode]?.strings[key] ?? key
        for (i, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(i)}", with: "\(arg)")
        }
        return text
    }

    // MARK: Caricamento

    static func loadPacks() -> [String: LanguagePack] {
        guard let folder = languagesFolder(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [:] }
        var result: [String: LanguagePack] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            do {
                let pack = try JSONDecoder().decode(LanguagePack.self, from: data)
                result[pack.code] = pack
            } catch {
                // Un pacchetto rotto non deve bloccare l'app: lo saltiamo.
                // I test (LocalizationTests) controllano che tutti si carichino.
                FileHandle.standardError.write(Data("Pacchetto lingua non valido \(file.lastPathComponent): \(error)\n".utf8))
            }
        }
        return result
    }

    /// Dove stanno i JSON: nel bundle di risorse del pacchetto Swift, che si
    /// trova accanto all'eseguibile (swift run, test) o dentro l'app (.app).
    static func languagesFolder() -> URL? {
        let bundleName = "AssistenteMac_AssistenteCore.bundle"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(bundleName)) }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() { candidates.append(exe.appendingPathComponent(bundleName)) }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        // Test: il bundle di risorse sta accanto al bundle dei test.
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName))
        }
        // Sviluppo e test: la cartella sorgente (accanto a questo file).
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Languages")
        for url in candidates {
            let folder = url.appendingPathComponent("Languages")
            if FileManager.default.fileExists(atPath: folder.path) { return folder }
            // Alcune versioni di SwiftPM mettono le risorse in Contents/Resources.
            let nested = url.appendingPathComponent("Contents/Resources/Languages")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
}
