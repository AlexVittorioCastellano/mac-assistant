import Foundation

public enum SlowMacDiagnosis {
    public static func findings(for s: SystemSnapshot) -> [Finding] {
        var result: [Finding] = []

        if s.cpuUsagePercent >= 85 {
            result.append(.init(id: "cpu", severity: .critical,
                                title: L.t("slow.cpu.critical", Fmt.percent(s.cpuUsagePercent))))
        } else if s.cpuUsagePercent >= 60 {
            result.append(.init(id: "cpu", severity: .warning,
                                title: L.t("slow.cpu.warning", Fmt.percent(s.cpuUsagePercent))))
        }

        if let top = s.topByCPU(1).first, top.cpuPercent >= 80, s.cpuUsagePercent < 40 {
            result.append(.init(id: "topcpu", severity: .info,
                                title: L.t("slow.topcpu.info", top.name)))
        } else if let top = s.topByCPU(1).first, top.cpuPercent >= 80 {
            if isSystem(top) {
                result.append(.init(id: "topcpu", severity: .warning,
                                    title: L.t("slow.topcpu.system", top.name),
                                    advice: L.t("slow.topcpu.system.advice")))
            } else {
                result.append(.init(id: "topcpu", severity: .warning,
                                    title: L.t("slow.topcpu.app", top.name),
                                    advice: L.t("slow.topcpu.app.advice", top.name)))
            }
        }

        switch s.memory.pressure {
        case .critical:
            result.append(.init(id: "mem", severity: .critical, title: L.t("slow.mem.critical"),
                                advice: L.t("slow.mem.advice")))
        case .warning:
            result.append(.init(id: "mem", severity: .warning, title: L.t("slow.mem.warning"),
                                advice: L.t("slow.mem.advice")))
        case .normal:
            break
        }

        if s.memory.swapUsedBytes >= 2 * 1_073_741_824 {
            result.append(.init(id: "swap", severity: .warning,
                                title: L.t("slow.swap", Fmt.gb(s.memory.swapUsedBytes)),
                                advice: L.t("slow.swap.advice")))
        }

        if let top = s.topByMemory(1).first, s.memory.totalBytes > 0,
           Double(top.residentBytes) / Double(s.memory.totalBytes) >= 0.25 {
            result.append(.init(id: "topmem", severity: .info,
                                title: L.t("slow.topmem", top.name, Fmt.size(top.residentBytes)),
                                advice: isSystem(top) ? nil : L.t("slow.topmem.advice", top.name)))
        }

        switch s.thermal {
        case .critical:
            result.append(.init(id: "heat", severity: .critical, title: L.t("slow.heat.critical"),
                                advice: L.t("slow.heat.advice")))
        case .serious:
            result.append(.init(id: "heat", severity: .warning, title: L.t("slow.heat.warning"),
                                advice: L.t("slow.heat.advice")))
        default:
            break
        }

        let days = Fmt.days(s.uptime)
        if days >= 14 {
            result.append(.init(id: "uptime", severity: .info, title: L.t("slow.uptime", days),
                                advice: L.t("slow.uptime.advice")))
        }

        if result.isEmpty {
            result.append(.init(id: "ok", severity: .ok, title: L.t("slow.ok")))
        }
        return result.sorted { $0.severity > $1.severity }
    }

    static func isSystem(_ p: ProcessGroup) -> Bool {
        p.isSystem || KnownProcesses.notes[p.name] != nil
    }

    static var instructions: String { Prompts.base }

    static func pressureWord(_ p: MemoryPressure) -> String {
        switch p {
        case .normal: L.t("level.pressure.normal")
        case .warning: L.t("level.pressure.warning")
        case .critical: L.t("level.pressure.critical")
        }
    }

    static func thermalWord(_ t: ThermalLevel) -> String {
        switch t {
        case .nominal, .fair: L.t("level.thermal.normal")
        case .serious: L.t("level.thermal.serious")
        case .critical: L.t("level.thermal.critical")
        }
    }

    public static func request(question: String, snapshot s: SystemSnapshot, findings: [Finding]) -> AIRequest {
        let byCPU = s.topByCPU(8), byMem = s.topByMemory(8)
        func list(_ items: [ProcessGroup], system: Bool, _ value: (ProcessGroup) -> String) -> String {
            let chosen = items.filter { isSystem($0) == system && ($0.cpuPercent >= 10 || $0.residentBytes >= 512 << 20) }.prefix(3)
            return chosen.isEmpty ? L.t("common.none") : chosen.map { "\($0.name) \(value($0))" }.joined(separator: ", ")
        }
        let cpu: (ProcessGroup) -> String = { Fmt.percent($0.cpuPercent) }
        let mem: (ProcessGroup) -> String = { Fmt.size($0.residentBytes) }

        let pressure = Self.pressureWord(s.memory.pressure)
        let thermal = Self.thermalWord(s.thermal)

        let shown = Set(byCPU.filter { isSystem($0) && $0.cpuPercent >= 10 }.prefix(3).map(\.name))
        let notes = shown.sorted().compactMap { name in
            KnownProcesses.notes[name].map { "- \(name): \($0)" }
        }

        if findings.allSatisfy({ $0.severity == .ok }) {
            let prompt = L.t("slow.prompt.ok", question, Fmt.percent(s.cpuUsagePercent), pressure, thermal)
            return AIRequest(instructions: instructions, prompt: prompt)
        }

        var prompt = L.t("slow.prompt", question, findings.map { "- \($0.title)" }.joined(separator: "\n"),
                         Fmt.percent(s.cpuUsagePercent), Fmt.gb(s.memory.usedBytes), Fmt.gb(s.memory.totalBytes),
                         pressure, thermal, list(byCPU, system: false, cpu), list(byMem, system: false, mem),
                         list(byCPU, system: true, cpu))
        if !notes.isEmpty {
            prompt += "\n\n" + L.t("slow.prompt.notes") + "\n" + notes.joined(separator: "\n")
        }
        prompt += "\n\n" + L.t("slow.prompt.end")
        return AIRequest(instructions: instructions, prompt: prompt)
    }
}
