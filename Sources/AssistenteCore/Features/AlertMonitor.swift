import Foundation

public struct MacAlert: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case cpuHog, memory, heat, disk }

    public var id: String
    public var kind: Kind
    public var title: String
    public var body: String

    public var question: String
}

public struct AlertMonitor: Sendable {
    public struct Rules: Sendable {
        public var cpuThreshold: Double = 80

        public var cpuDuration: TimeInterval = 10 * 60
        public var memoryDuration: TimeInterval = 5 * 60
        public var heatDuration: TimeInterval = 5 * 60

        public var diskFreeRatio: Double = 0.10
        public var diskFreeBytes: UInt64 = 10 * 1_073_741_824

        public var repeatAfter: TimeInterval = 6 * 3600
        public init() {}
    }

    public var rules = Rules()

    private var since: [String: Date] = [:]

    private var lastSent: [String: Date] = [:]

    public private(set) var active: [MacAlert] = []

    public init(rules: Rules = Rules()) { self.rules = rules }

    public mutating func update(snapshot s: SystemSnapshot, diskFree: UInt64, diskTotal: UInt64,
                                now: Date = Date()) -> [MacAlert] {
        var current: [MacAlert] = []
        var seen = Set<String>()

        func elapsed(_ id: String) -> String {
            let minutes = Int(now.timeIntervalSince(since[id] ?? now) / 60)
            switch minutes {
            case ..<2: return L.t("alert.elapsed.few")
            case ..<60: return L.t("alert.elapsed.minutes", minutes)
            case ..<120: return L.t("alert.elapsed.hour")
            default: return L.t("alert.elapsed.hours", minutes / 60)
            }
        }

        func check(_ makeAlert: () -> MacAlert, id: String, isTrue: Bool, duration: TimeInterval) {
            guard isTrue else { return }
            seen.insert(id)
            let start = since[id] ?? now
            since[id] = start
            if now.timeIntervalSince(start) >= duration { current.append(makeAlert()) }
        }

        for p in s.processes where !p.isSystem && p.cpuPercent >= rules.cpuThreshold {
            let id = "cpuHog:\(p.name)"
            check({ MacAlert(id: id, kind: .cpuHog,
                             title: L.t("alert.cpu.title", p.name, elapsed(id)),
                             body: L.t("alert.cpu.body"),
                             question: L.t("question.processNamed", p.name)) },
                  id: id, isTrue: true, duration: rules.cpuDuration)
        }

        check({ MacAlert(id: "memory", kind: .memory, title: L.t("alert.memory.title", elapsed("memory")),
                         body: L.t("alert.memory.body"),
                         question: Assistant.slowMacQuestion) },
              id: "memory", isTrue: s.memory.pressure == .critical, duration: rules.memoryDuration)

        check({ MacAlert(id: "heat", kind: .heat, title: L.t("alert.heat.title", elapsed("heat")),
                         body: L.t("alert.heat.body"),
                         question: Assistant.slowMacQuestion) },
              id: "heat", isTrue: s.thermal == .serious || s.thermal == .critical, duration: rules.heatDuration)

        let lowDisk = diskTotal > 0 && (Double(diskFree) / Double(diskTotal) < rules.diskFreeRatio
                                        || diskFree < rules.diskFreeBytes)
        check({ MacAlert(id: "disk", kind: .disk, title: L.t("alert.disk.title"),
                         body: L.t("alert.disk.body", Fmt.size(diskFree)),
                         question: Assistant.diskQuestion) },
              id: "disk", isTrue: lowDisk, duration: 0)

        since = since.filter { seen.contains($0.key) }
        active = current

        let fresh = current.filter { a in
            guard let last = lastSent[a.id] else { return true }
            return now.timeIntervalSince(last) >= rules.repeatAfter
        }
        for a in fresh { lastSent[a.id] = now }
        return fresh
    }
}
