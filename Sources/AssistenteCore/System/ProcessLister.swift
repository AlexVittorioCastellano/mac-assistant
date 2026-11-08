import Foundation

public enum ProcessLister {
    public static func list() throws -> [ProcessSample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")

        process.arguments = ["-A", "-o", "pid=,pcpu=,rss=,user=,comm="]

        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

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

            let hasPath = command.hasPrefix("/")

            let name = command.contains("/") ? (command.split(separator: "/").last.map(String.init) ?? command) : command
            return ProcessSample(pid: pid, cpuPercent: cpu, residentBytes: rssKB * 1024,
                                 user: String(user), name: name, path: hasPath ? command : nil)
        }
    }

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

    static func logicalName(_ name: String) -> String {
        if let range = name.range(of: " Helper") {
            return String(name[..<range.lowerBound])
        }
        return name
    }
}
