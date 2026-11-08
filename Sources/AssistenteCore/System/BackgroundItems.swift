import Foundation

/// Un programma che macOS avvia da solo (LaunchAgent o LaunchDaemon).
public struct BackgroundItem: Sendable, Equatable {
    public enum Scope: Sendable { case currentUser, allUsers, system }

    public var label: String
    public var plistPath: String
    /// Il programma avviato (primo elemento di ProgramArguments o Program).
    public var executable: String?
    /// Gli argomenti, per capire se esegue uno script.
    public var arguments: [String]
    public var scope: Scope

    public init(label: String, plistPath: String, executable: String?, arguments: [String] = [], scope: Scope) {
        self.label = label
        self.plistPath = plistPath
        self.executable = executable
        self.arguments = arguments
        self.scope = scope
    }
}

/// Un'app installata, con la sua firma.
public struct InstalledApp: Sendable, Equatable {
    public var name: String
    public var path: String
    public var trust: CodeTrust
}

/// Legge programmi in background e app installate. Solo lettura, niente rete.
public struct SecurityScanner: Sendable {
    public init() {}

    public struct Result: Sendable {
        public var items: [(BackgroundItem, CodeTrust)]
        public var apps: [InstalledApp]
    }

    public func scan(includeApps: Bool = true) async -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders: [(String, BackgroundItem.Scope)] = [
            ("\(home)/Library/LaunchAgents", .currentUser),
            ("/Library/LaunchAgents", .allUsers),
            ("/Library/LaunchDaemons", .system),
        ]
        let items = folders.flatMap { Self.items(in: $0.0, scope: $0.1) }
        let checkedItems = items.map { item in (item, item.executable.map(CodeTrust.check(path:)) ?? .missing) }

        var apps: [InstalledApp] = []
        if includeApps {
            let me = Bundle.main.bundlePath
            let appFolders = ["/Applications", "\(home)/Applications"]
            let paths = appFolders.flatMap { folder in
                ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
                    .filter { $0.hasSuffix(".app") }.map { "\(folder)/\($0)" }
            }.filter { $0 != me }  // non controlliamo noi stessi
            apps = await withTaskGroup(of: InstalledApp.self) { group in
                for path in paths {
                    group.addTask {
                        InstalledApp(name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                     path: path, trust: CodeTrust.check(path: path))
                    }
                }
                var result: [InstalledApp] = []
                for await app in group { result.append(app) }
                return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
        return Result(items: checkedItems, apps: apps)
    }

    static func items(in folder: String, scope: BackgroundItem.Scope) -> [BackgroundItem] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return files.filter { $0.hasSuffix(".plist") }.compactMap { file in
            let path = "\(folder)/\(file)"
            return parse(plistAt: path, scope: scope)
        }
    }

    static func parse(plistAt path: String, scope: BackgroundItem.Scope) -> BackgroundItem? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let label = plist["Label"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let args = plist["ProgramArguments"] as? [String] ?? []
        let program = plist["Program"] as? String ?? args.first
        return BackgroundItem(label: label, plistPath: path, executable: program, arguments: args, scope: scope)
    }
}
