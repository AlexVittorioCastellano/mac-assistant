import Foundation

public enum SecurityScan {
    static let knownUnwanted = [
        "mackeeper", "advanced mac cleaner", "advancedmaccleaner", "mac auto fixer", "macautofixer",
        "mac cleanup pro", "maccleanuppro", "smart mac booster", "mac tonic", "mactonic",
        "search baron", "searchbaron", "search marquis", "searchmarquis", "shlayer", "pirrit",
        "genieo", "vsearch", "bundlore", "adload", "mughthesec",
    ]

    static let scriptRunners: Set<String> = ["bash", "sh", "zsh", "python", "python3", "osascript", "curl", "perl", "ruby", "node"]

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

    static var brokenExplanation: String { L.t("security.broken") }

    static var removeBackground: String { L.t("security.remove") }

    public static func verdict(for item: BackgroundItem, trust: CodeTrust) -> Verdict {
        let program = item.executable ?? ""
        let name = displayName(item)
        let isApple = item.label.hasPrefix("com.apple.") && trust == .apple

        if isKnownUnwanted(item.label) || isKnownUnwanted(program) {
            return Verdict(severity: .critical, title: L.t("security.bg.unwanted", name),
                           advice: L.t("security.bg.unwanted.advice", removeBackground))
        }
        if trust == .broken {
            return Verdict(severity: .warning, title: L.t("security.bg.broken", name),
                           advice: L.t("security.bg.broken.advice", brokenExplanation, removeBackground))
        }
        let base = URL(fileURLWithPath: program).lastPathComponent
        if !isApple, scriptRunners.contains(base), item.arguments.count > 1 {
            return Verdict(severity: .warning, title: L.t("security.bg.script", name),
                           advice: L.t("security.bg.script.advice", removeBackground))
        }
        if oddLocations.contains(where: program.hasPrefix) || URL(fileURLWithPath: program).lastPathComponent.hasPrefix(".") {
            return Verdict(severity: .warning, title: L.t("security.bg.hidden", name),
                           advice: L.t("security.bg.hidden.advice", removeBackground))
        }
        switch trust {
        case .missing:
            return Verdict(severity: .info, title: L.t("security.bg.missing", name),
                           advice: L.t("security.bg.missing.advice", removeBackground))
        case .unsigned, .unverified:
            return Verdict(severity: .warning, title: L.t("security.bg.unverified", name),
                           advice: L.t("security.bg.unverified.advice", removeBackground))
        case .apple:
            return Verdict(severity: .ok, title: L.t("security.bg.apple", name), advice: nil)
        case .appStore:
            return Verdict(severity: .ok, title: L.t("security.bg.appstore", name), advice: nil)
        case .identifiedDeveloper(let dev):
            return Verdict(severity: .ok, title: L.t("security.bg.developer", name, dev), advice: nil)
        case .broken:
            return Verdict(severity: .critical, title: L.t("security.bg.generic", name), advice: nil)
        }
    }

    public static func verdict(for app: InstalledApp) -> Verdict? {
        if isKnownUnwanted(app.name) {
            return Verdict(severity: .critical, title: L.t("security.app.unwanted", app.name),
                           advice: L.t("security.app.unwanted.advice"))
        }
        switch app.trust {
        case .broken:
            return Verdict(severity: .warning, title: L.t("security.app.broken", app.name),
                           advice: L.t("security.app.broken.advice", brokenExplanation))
        case .unsigned, .unverified:
            return Verdict(severity: .warning, title: L.t("security.app.unverified", app.name),
                           advice: L.t("security.app.unverified.advice"))
        default:
            return nil
        }
    }

    static func displayName(_ item: BackgroundItem) -> String {
        if let exe = item.executable, !exe.isEmpty {
            if let app = ProcessKind.outermostAppBundlePath(in: exe) {
                return URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
            }
            return URL(fileURLWithPath: exe).lastPathComponent
        }
        return item.label
    }

    public static func findings(for result: SecurityScanner.Result) -> [Finding] {
        var rows: [Finding] = []
        for (i, entry) in result.items.enumerated() {
            let (item, trust) = entry

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

        let sorted = rows.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
        let problems = rows.filter { $0.severity >= .warning }.count
        let worst = rows.map(\.severity).max() ?? .ok

        let headline = Finding(
            id: "overall", severity: problems == 0 ? .ok : worst,
            title: problems == 0 ? L.t("security.overall.ok")
                : problems == 1 ? L.t("security.overall.one") : L.t("security.overall.many", problems),
            symbol: problems == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")

        var summary: [Finding] = []
        let background = rows.filter { $0.id.hasPrefix("bg") }.count
        summary.append(Finding(id: "bgcount", severity: .info,
                               title: background == 0 ? L.t("security.bgcount.none") : L.t("security.bgcount", background),
                               symbol: "gearshape.2"))
        if !result.apps.isEmpty {
            let ok = result.apps.count - appProblems.count
            summary.append(Finding(id: "appcount", severity: .info,
                                   title: L.t("security.appcount", result.apps.count, ok),
                                   symbol: "app.badge.checkmark"))
        }
        return [headline] + sorted + summary
    }

    public static func problemCount(_ result: SecurityScanner.Result) -> Int {
        findings(for: result).filter { $0.id != "overall" && $0.severity >= .warning }.count
    }
}
