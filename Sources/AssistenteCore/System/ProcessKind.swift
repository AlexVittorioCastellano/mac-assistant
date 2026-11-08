import Foundation
import Security

/// Che tipo di processo è, dedotto dal percorso dell'eseguibile.
///
/// È la base per dire all'utente se un processo si può chiudere: lo decide
/// questo codice (regole chiare e testabili), non il modello AI.
public enum ProcessKind: Sendable, Equatable {
    /// Parte di macOS (es. /System/..., /usr/libexec/...).
    case macOS
    /// Un'app vera e propria, che l'utente può chiudere con ⌘Q.
    case app(name: String)
    /// Un pezzo di un'app (helper, estensione, servizio interno).
    case appComponent(appName: String)
    /// Programma in background installato da terzi (driver, aggiornamenti…).
    case background
    /// Non si riesce a capire (es. processo senza percorso).
    case unknown

    public static func classify(path: String?, user: String) -> ProcessKind {
        let systemUser = user == "root" || user.hasPrefix("_")
        guard let path, path.hasPrefix("/") else {
            return systemUser ? .macOS : .unknown
        }

        // 1. App in una cartella Applicazioni (anche quelle di Apple come
        //    Safari o Mail, che si possono chiudere normalmente).
        if path.contains("/Applications/"), let app = appBundle(in: path) {
            return app.isMainExecutable ? .app(name: app.name) : .appComponent(appName: app.name)
        }

        // 2. Componenti di sistema.
        let systemPrefixes = ["/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/"]
        if systemPrefixes.contains(where: path.hasPrefix) && !path.hasPrefix("/usr/local/") {
            return .macOS
        }

        // 3. Componenti di Apple fuori dalle cartelle di sistema
        //    (es. ~/Library/Application Support/.com.apple.metadata.mds/mdworker_shared).
        if path.contains("/com.apple.") || path.contains("/.com.apple.") {
            return .macOS
        }

        // 4. Tutto il resto: programmi installati da terzi che girano in background.
        return .background
    }

    /// Versione più accurata (ma più lenta) per un singolo processo: se il
    /// percorso fa pensare a un programma di terze parti, controlla la firma
    /// digitale. Se è firmato da Apple come parte di macOS, è di sistema.
    public static func classifyVerifyingSignature(path: String?, user: String) -> ProcessKind {
        let kind = classify(path: path, user: user)
        if kind == .background, let path, isSignedByAppleAsSystem(path) { return .macOS }
        return kind
    }

    /// `true` se l'eseguibile è firmato da Apple come software di sistema
    /// (requisito "anchor apple": non vale per le app di terze parti, nemmeno
    /// quelle dell'App Store). Solo lettura.
    static func isSignedByAppleAsSystem(_ path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// Il primo bundle `.app` nel percorso, e se il processo ne è l'eseguibile principale.
    static func appBundle(in path: String) -> (name: String, isMainExecutable: Bool)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        let bundlePath = "/" + parts[...i].joined(separator: "/")
        let rest = parts[(i + 1)...]
        let isMain = rest.count == 3 && rest.first == "Contents" && rest.dropFirst().first == "MacOS"
        return (displayName(ofBundleAt: bundlePath), isMain)
    }

    /// Il percorso del primo bundle `.app` che contiene l'eseguibile
    /// (es. l'app di cui un Helper fa parte). Serve per mostrarne l'icona.
    public static func outermostAppBundlePath(in path: String?) -> String? {
        guard let path, path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + parts[...i].joined(separator: "/")
    }

    /// Nome leggibile dell'app (es. "Visual Studio Code" invece di "Electron").
    static func displayName(ofBundleAt path: String) -> String {
        let info = Bundle(path: path)?.infoDictionary
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = (info?[key] as? String).map(cleaned), !name.isEmpty { return name }
        }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    /// Alcune app (es. WhatsApp) mettono nel nome caratteri invisibili di
    /// direzione del testo: li togliamo.
    static func cleaned(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespaces)
    }
}
