import Foundation

public enum ProcessExplainer {
    public struct Details: Sendable, Equatable {
        public var group: ProcessGroup
        public var note: String?

        public var isExactMatch = true
    }

    public static func find(_ name: String, in samples: [ProcessSample]) -> Details? {
        func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

        var matching = samples.filter { same($0.name, name) }

        if matching.isEmpty {
            matching = samples.filter { same(ProcessLister.logicalName($0.name), name) }
        }

        var exact = true
        if matching.isEmpty {
            let partial = samples.filter { $0.name.localizedCaseInsensitiveContains(name) }
            if Set(partial.map { ProcessLister.logicalName($0.name) }).count == 1 { matching = partial; exact = false }
        }
        guard !matching.isEmpty else { return nil }

        let logical = ProcessLister.logicalName(matching[0].name)
        let main = matching.first { $0.name == logical } ?? matching[0]
        let displayName = matching.allSatisfy { $0.name == main.name } ? main.name : logical
        let kind = ProcessKind.classifyVerifyingSignature(path: main.path, user: main.user)
        let group = ProcessGroup(
            name: displayName,
            instanceCount: matching.count,
            cpuPercent: matching.reduce(0) { $0 + $1.cpuPercent },
            residentBytes: matching.reduce(0) { $0 + $1.residentBytes },
            isSystem: kind == .macOS,
            pids: matching.map(\.pid),
            path: main.path,
            kind: kind)
        return Details(group: group, note: KnownProcesses.note(for: main.name), isExactMatch: exact)
    }

    public static func suggestions(from samples: [ProcessSample], limit: Int = 8) -> [ProcessGroup] {
        let me = ProcessInfo.processInfo.processIdentifier
        let groups = ProcessLister.group(samples).filter { !$0.pids.contains(me) }
        let byCPU = groups.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit / 2)
        let byMem = groups.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit)
        var seen = Set<String>()
        return Array((byCPU + byMem).filter { seen.insert($0.name).inserted }.prefix(limit))
    }

    public static func symbol(for g: ProcessGroup) -> String {
        g.isSystem ? "gearshape.fill" : "app.dashed"
    }

    public static func findings(for d: Details) -> [Finding] {
        let g = d.group
        var result: [Finding] = []

        let icon = ProcessKind.outermostAppBundlePath(in: g.path)
        let symbol = symbol(for: g)

        switch g.kind {
        case .macOS:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.macos"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .critical, title: L.t("process.close.macos"),
                                advice: g.cpuPercent >= 50
                                    ? L.t("process.close.macos.advice")
                                    : nil))
        case .app(let name):
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.app", name),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .ok, title: L.t("process.close.app"),
                                advice: L.t("process.close.app.advice")))
        case .appComponent(let app):
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.component", app),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .info, title: L.t("process.close.component", app),
                                advice: L.t("process.close.component.advice", app)))
        case .background:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.background"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .warning, title: L.t("process.close.background"),
                                advice: L.t("process.close.background.advice")))
        case .unknown:
            result.append(.init(id: "kind", severity: .info, title: L.t("process.kind.unknown"),
                                iconPath: icon, symbol: symbol))
            result.append(.init(id: "close", severity: .warning, title: L.t("process.close.unknown")))
        }

        var usage = L.t("process.usage", Fmt.percent(g.cpuPercent), Fmt.size(g.residentBytes))
        if g.instanceCount > 1 { usage += L.t("process.usage.copies", g.instanceCount) }
        result.append(.init(id: "usage", severity: .info, title: usage))
        return result
    }

    public static func request(question: String, details d: Details) -> AIRequest {
        let g = d.group
        let kind = switch g.kind {
            case .macOS: L.t("process.prompt.kind.macos")
            case .app(let name): L.t("process.prompt.kind.app", name)
            case .appComponent(let app): L.t("process.prompt.kind.component", app)
            case .background: L.t("process.prompt.kind.background")
            case .unknown: L.t("process.prompt.kind.unknown")
        }
        let verdict = findings(for: d).first { $0.id == "close" }?.title ?? ""

        var prompt = L.t("process.prompt", question, g.name, kind, verdict)
        if let note = d.note {
            prompt += "\n" + L.t("process.prompt.note", note)
        } else if let path = g.path {
            prompt += "\n" + L.t("process.prompt.path", path)
        }
        prompt += "\n\n" + L.t("process.prompt.end")
        return AIRequest(instructions: Prompts.base, prompt: prompt)
    }

    public static func notFoundMessage(for name: String) -> String {
        if let note = KnownProcesses.note(for: name) {
            return L.t("process.notfound.known", name, note)
        }
        return L.t("process.notfound", name)
    }
}
