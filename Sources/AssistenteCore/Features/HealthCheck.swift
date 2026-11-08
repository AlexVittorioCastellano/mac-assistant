import Foundation

public enum HealthCheck {
    public struct Input: Sendable {
        public var snapshot: SystemSnapshot
        public var disk: (total: UInt64, free: UInt64)
        public var status: MacStatus

        public var suspicious: Int?
        public var now: Date

        public init(snapshot: SystemSnapshot, disk: (total: UInt64, free: UInt64), status: MacStatus,
                    suspicious: Int? = nil, now: Date = Date()) {
            self.snapshot = snapshot
            self.disk = disk
            self.status = status
            self.suspicious = suspicious
            self.now = now
        }
    }

    public static func findings(for input: Input) -> [Finding] {
        let items = checks(input)

        let sorted = items.enumerated()
            .sorted { ($0.element.severity, -$0.offset) > ($1.element.severity, -$1.offset) }
            .map(\.element)
        let problems = items.filter { $0.severity >= .warning }.count
        return [headline(problems: problems, worst: items.map(\.severity).max() ?? .ok)] + sorted
    }

    static func headline(problems: Int, worst: Finding.Severity) -> Finding {
        let title = switch problems {
            case 0: L.t("health.overall.ok")
            case 1: L.t("health.overall.one")
            default: L.t("health.overall.many", problems)
        }
        let symbol = problems == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
        return Finding(id: "overall", severity: problems == 0 ? .ok : worst, title: title, symbol: symbol)
    }

    static func checks(_ input: Input) -> [Finding] {
        var result: [Finding] = []
        let s = input.status

        let slow = SlowMacDiagnosis.findings(for: input.snapshot).filter { $0.id != "uptime" && $0.id != "ok" }
        if let worst = slow.max(by: { $0.severity < $1.severity }), worst.severity >= .warning {
            result.append(.init(id: "speed", severity: .warning, title: L.t("health.speed.bad", worst.title.lowercasedFirst),
                                advice: L.t("health.speed.bad.advice"), symbol: "speedometer"))
        } else {
            result.append(.init(id: "speed", severity: .ok, title: L.t("health.speed.ok"), symbol: "speedometer"))
        }

        let usage = DiskUsage(totalBytes: input.disk.total, freeBytes: input.disk.free, purgeableBytes: 0,
                              macOSBytes: 0, items: [], localSnapshotCount: 0)
        switch DiskSpaceAnalysis.level(usage) {
        case .ok:
            result.append(.init(id: "disk", severity: .ok, title: L.t("health.disk.ok", Fmt.size(input.disk.free)), symbol: "internaldrive"))
        case let level:
            result.append(.init(id: "disk", severity: level, title: L.t("health.disk.low", Fmt.size(input.disk.free)),
                                advice: L.t("health.disk.low.advice"), symbol: "internaldrive"))
        }

        switch s.backup {
        case .notConfigured:
            result.append(.init(id: "backup", severity: .warning, title: L.t("health.backup.none"),
                                advice: L.t("health.backup.none.advice"),
                                symbol: "clock.arrow.circlepath"))
        case .configured(let last?):
            let days = Int(input.now.timeIntervalSince(last) / 86_400)
            if days > 7 {
                result.append(.init(id: "backup", severity: .warning, title: L.t("health.backup.old", days),
                                    advice: L.t("health.backup.old.advice"),
                                    symbol: "clock.arrow.circlepath"))
            } else {
                let when = days == 0 ? L.t("health.backup.today") : days == 1 ? L.t("health.backup.yesterday") : L.t("health.backup.daysAgo", days)
                result.append(.init(id: "backup", severity: .ok, title: L.t("health.backup.last", when), symbol: "clock.arrow.circlepath"))
            }
        case .configured(nil):
            result.append(.init(id: "backup", severity: .ok, title: L.t("health.backup.configured"), symbol: "clock.arrow.circlepath"))
        case .unknown:
            break
        }

        if let on = s.fileVaultOn {
            result.append(on
                ? .init(id: "filevault", severity: .ok, title: L.t("health.filevault.on"), symbol: "lock.fill")
                : .init(id: "filevault", severity: .warning, title: L.t("health.filevault.off"),
                        advice: L.t("health.filevault.off.advice"),
                        symbol: "lock.open.fill"))
        }
        if s.gatekeeperOn == false {
            result.append(.init(id: "gatekeeper", severity: .critical,
                                title: L.t("health.gatekeeper.off"),
                                advice: L.t("health.gatekeeper.off.advice"),
                                symbol: "shield.slash.fill"))
        } else if s.gatekeeperOn == true {
            result.append(.init(id: "gatekeeper", severity: .ok, title: L.t("health.gatekeeper.on"), symbol: "checkmark.shield.fill"))
        }
        if s.sipOn == false {
            result.append(.init(id: "sip", severity: .critical,
                                title: L.t("health.sip.off"),
                                advice: L.t("health.sip.off.advice"),
                                symbol: "shield.slash.fill"))
        } else if s.sipOn == true {
            result.append(.init(id: "sip", severity: .ok, title: L.t("health.sip.on"), symbol: "checkmark.shield.fill"))
        }
        if s.firewallOn == false {
            result.append(.init(id: "firewall", severity: .info, title: L.t("health.firewall.off"),
                                advice: L.t("health.firewall.off.advice"),
                                symbol: "flame"))
        } else if s.firewallOn == true {
            result.append(.init(id: "firewall", severity: .ok, title: L.t("health.firewall.on"), symbol: "flame"))
        }

        if let n = input.suspicious {
            result.append(n == 0
                ? .init(id: "apps", severity: .ok, title: L.t("health.apps.ok"), symbol: "checkmark.shield.fill")
                : .init(id: "apps", severity: .warning,
                        title: n == 1 ? L.t("health.apps.one") : L.t("health.apps.many", n),
                        advice: L.t("health.apps.advice"),
                        symbol: "exclamationmark.shield.fill"))
        }

        if let pending = s.pendingUpdates, pending > 0 {
            result.append(.init(id: "updates", severity: .warning,
                                title: pending == 1 ? L.t("health.updates.one") : L.t("health.updates.many", pending),
                                advice: L.t("health.updates.pending.advice"),
                                symbol: "arrow.down.circle"))
        } else if s.automaticUpdatesOn == false {
            result.append(.init(id: "updates", severity: .warning, title: L.t("health.updates.auto.off"),
                                advice: L.t("health.updates.auto.off.advice"),
                                symbol: "arrow.down.circle"))
        } else if s.automaticUpdatesOn == true {
            result.append(.init(id: "updates", severity: .ok, title: L.t("health.updates.auto.on"), symbol: "arrow.down.circle"))
        }

        if let b = s.battery {
            if b.healthPercent < 80 {
                result.append(.init(id: "battery", severity: .warning,
                                    title: L.t("health.battery.worn", b.healthPercent),
                                    advice: L.t("health.battery.worn.advice"),
                                    symbol: "battery.25percent"))
            } else {
                result.append(.init(id: "battery", severity: .ok,
                                    title: L.t("health.battery.ok", b.healthPercent, b.cycleCount), symbol: "battery.100percent"))
            }
        }

        let days = Fmt.days(input.snapshot.uptime)
        if days >= 14 {
            result.append(.init(id: "uptime", severity: .info, title: L.t("health.uptime", days),
                                advice: L.t("health.uptime.advice"),
                                symbol: "arrow.clockwise"))
        }
        return result
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
