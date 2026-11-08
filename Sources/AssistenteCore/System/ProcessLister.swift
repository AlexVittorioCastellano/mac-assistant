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
        // -A tutti i processi, -c solo il nome dell'eseguibile.
        // Il nome va per ultimo perché può contenere spazi.
        process.arguments = ["-Ac", "-o", "pid=,pcpu=,rss=,user=,comm="]
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
            let name = rest.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return ProcessSample(pid: pid, cpuPercent: cpu, residentBytes: rssKB * 1024,
                                 user: String(user), name: name)
        }
    }

    /// Raggruppa i processi di una stessa app (es. i vari "Helper").
    public static func group(_ samples: [ProcessSample]) -> [ProcessGroup] {
        var groups: [String: ProcessGroup] = [:]
        for s in samples {
            let key = logicalName(s.name)
            let system = s.user == "root" || s.user.hasPrefix("_")
            if var g = groups[key] {
                g.instanceCount += 1
                g.cpuPercent += s.cpuPercent
                g.residentBytes += s.residentBytes
                g.isSystem = g.isSystem && system
                g.pids.append(s.pid)
                groups[key] = g
            } else {
                groups[key] = ProcessGroup(name: key, instanceCount: 1, cpuPercent: s.cpuPercent,
                                           residentBytes: s.residentBytes, isSystem: system, pids: [s.pid])
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
