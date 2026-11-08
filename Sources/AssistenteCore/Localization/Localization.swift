import Foundation

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

    public var code: String

    public var name: String

    public var locale: String
    var strings: [String: String]
    var router: Router
    var guides: [Guide]
    var processes: [String: String]
    var messages: [Message]

    public var foundationLocale: Locale { Locale(identifier: locale) }
}

public enum L {
    public static let fallbackCode = "en"

    @TaskLocal public static var taskLanguage: String?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _override: String?

    public static var override: String? {
        get { lock.withLock { _override } ?? ProcessInfo.processInfo.environment["ASSISTENTE_LINGUA"] }
        set { lock.withLock { _override = newValue } }
    }

    public static let packs: [String: LanguagePack] = loadPacks()

    public static var available: [LanguagePack] {
        packs.values.sorted { $0.name < $1.name }
    }

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

    public static func t(_ key: String, _ args: Any...) -> String {
        var text = current.strings[key] ?? packs[fallbackCode]?.strings[key] ?? key
        for (i, arg) in args.enumerated() {
            text = text.replacingOccurrences(of: "{\(i)}", with: "\(arg)")
        }
        return text
    }

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
                FileHandle.standardError.write(Data("Pacchetto lingua non valido \(file.lastPathComponent): \(error)\n".utf8))
            }
        }
        return result
    }

    static func languagesFolder() -> URL? {
        let bundleName = "AssistenteMac_AssistenteCore.bundle"
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent(bundleName)) }
        if let exe = Bundle.main.executableURL?.deletingLastPathComponent() { candidates.append(exe.appendingPathComponent(bundleName)) }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))

        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName))
        }

        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Languages")
        for url in candidates {
            let folder = url.appendingPathComponent("Languages")
            if FileManager.default.fileExists(atPath: folder.path) { return folder }

            let nested = url.appendingPathComponent("Contents/Resources/Languages")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
}
