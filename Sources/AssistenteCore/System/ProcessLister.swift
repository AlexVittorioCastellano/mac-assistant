import Foundation

/// Elenca i processi usando `/bin/ps`.
///
/// Usiamo `ps` invece delle API di basso livello perché, senza privilegi di
/// amministratore, è l'unico modo semplice per vedere anche i processi di
/// sistema (es. `kernel_task`). Solo lettura: non chiude nulla.
public enum ProcessLister {
    public static func list() throws -> [ProcessSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -A tutti i processi; `comm` è il percorso completo dell'eseguibile.
        // Va per ultimo perché può contenere spazi.
        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,user=,comm="]
        // Forza il punto decimale (con la lingua italiana `ps` usa la virgola).
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Leggere PRIMA di attendere, altrimenti con output lunghi si blocca.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Interpreta l'output di `ps`. Separato da `list()` per poterlo testare.
    static func parse(_ output: String) -> [ProcessSample] {
        output.split(separator: "\n").compactMap { line in
            var rest = Substring(line)
            func nextField() -> Substring? {
                rest = rest.drop { $0 == " " }
                guard !rest.isEmpty else { return nil }
                let field = rest.prefix { $0 != " " }
                rest = rest.dropFirst(field.count)
                return field
            }
            guard let pid = nextField().flatMap({ Int32($0) }),
                  let cpu = nextField().flatMap({ Double($0) }),
                  let rssKB = nextField().flatMap({ UInt64($0) }),
                  let user = nextField() else { return nil }
            let command = rest.trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return nil }
            // "/percorso/fino/a/Nome" -> nome "Nome", percorso completo.
            // Alcuni processi (es. kernel_task) non hanno un percorso.
            let hasPath = command.hasPrefix("/")
            // Anche i percorsi relativi ("./build/App") diventano solo "App".
            let name = command.contains("/") ? (command.split(separator: "/").last.map(String.init) ?? command) : command
            return ProcessSample(pid: pid, cpuPercent: cpu, residentBytes: rssKB * 1024,
                                 user: String(user), name: name, path: hasPath ? command : nil)
        }
    }

    /// Raggruppa i processi di una stessa app (es. i vari "Helper").
    public static func group(_ samples: [ProcessSample]) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        for s in samples {
            let key = logicalName(s.name)
            if var g = groups[key] {
                g.instanceCount += 1
                g.cpuPercent += s.cpuPercent
                g.residentBytes += s.residentBytes
                g.pids.append(s.pid)
                groups[key] = g
            } else {
                let kind = ProcessKind.classify(path: s.path, user: s.user)
                groups[key] = ProcessGroup(name: key, instanceCount: 1, cpuPercent: s.cpuPercent,
                                           residentBytes: s.residentBytes, isSystem: kind == .macOS,
                                           pids: [s.pid], path: s.path, kind: kind)
            }
        }
        return Array(groups.values)
    }

    /// "Google Chrome Helper (Renderer)" -> "Google Chrome".
    static func logicalName(_ name: String) -> String {
        if let range = name.range(of: " Helper") {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}
