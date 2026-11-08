import Testing
@testable import AssistenteCore

@Suite struct ProcessListerTests {
    @Test func parsesPsOutputWithSpacesInNames() {
        let output = """
          1   0.0  12000 root     launchd
        412  35.5 204800 alex     Google Chrome Helper (Renderer)
        413  10.0 102400 alex     Google Chrome
          0 120.0   4096 root     kernel_task
        """
        let samples = ProcessLister.parse(output)
        #expect(samples.count == 4)
        #expect(samples[1].name == "Google Chrome Helper (Renderer)")
        #expect(samples[1].cpuPercent == 35.5)
        #expect(samples[1].residentBytes == 204800 * 1024)

        let groups = ProcessLister.group(samples)
        let chrome = groups.first { $0.name == "Google Chrome" }
        #expect(chrome?.instanceCount == 2)
        #expect(chrome?.cpuPercent == 45.5)
        #expect(chrome?.isSystem == false)
        #expect(groups.first { $0.name == "kernel_task" }?.isSystem == true)
    }
}

@Suite struct DiagnosisTests {
    func snapshot(cpu: Double = 10, pressure: MemoryPressure = .normal,
                  thermal: ThermalLevel = .nominal, processes: [ProcessGroup] = []) -> SystemSnapshot {
        SystemSnapshot(
            cpuUsagePercent: cpu, coreCount: 8,
            memory: MemoryInfo(totalBytes: 16 << 30, usedBytes: 8 << 30, cachedBytes: 2 << 30,
                               compressedBytes: 0, swapUsedBytes: 0, pressure: pressure),
            thermal: thermal, uptime: 3600, processes: processes)
    }

    @Test func healthyMacSaysAllGood() {
        let f = SlowMacDiagnosis.findings(for: snapshot())
        #expect(f.map(\.id) == ["ok"])
    }

    @Test func detectsBusyCpuAndHeavyProcess() {
        let heavy = ProcessGroup(name: "Xcode", instanceCount: 1, cpuPercent: 250,
                                 residentBytes: 1 << 30, isSystem: false, pids: [1])
        let f = SlowMacDiagnosis.findings(for: snapshot(cpu: 90, processes: [heavy]))
        #expect(f.first?.id == "cpu")
        #expect(f.first?.severity == .critical)
        #expect(f.contains { $0.id == "topcpu" && $0.title.contains("Xcode") })
    }

    @Test func singleBusyProcessOnIdleMacIsOnlyInfo() {
        let p = ProcessGroup(name: "yes", instanceCount: 1, cpuPercent: 100,
                             residentBytes: 1 << 20, isSystem: false, pids: [9])
        let f = SlowMacDiagnosis.findings(for: snapshot(cpu: 12, processes: [p]))
        #expect(f.first { $0.id == "topcpu" }?.severity == .info)
        #expect(f.first { $0.id == "topcpu" }?.advice == nil)
    }

    @Test func neverAdvisesClosingSystemProcesses() {
        let k = ProcessGroup(name: "kernel_task", instanceCount: 1, cpuPercent: 300,
                             residentBytes: 6 << 30, isSystem: true, pids: [0])
        let advice = SlowMacDiagnosis.advice(from: SlowMacDiagnosis.findings(for: snapshot(cpu: 90, processes: [k])))
        #expect(!advice.isEmpty)
        #expect(!advice.contains { $0.contains("chiudi «kernel_task»") })
    }

    @Test func detectsMemoryPressureAndHeat() {
        let f = SlowMacDiagnosis.findings(for: snapshot(pressure: .critical, thermal: .serious))
        #expect(f.map(\.id).contains("mem"))
        #expect(f.map(\.id).contains("heat"))
    }

    @Test func promptContainsDataAndKnownProcessNotes() {
        let k = ProcessGroup(name: "kernel_task", instanceCount: 1, cpuPercent: 300,
                             residentBytes: 1 << 20, isSystem: true, pids: [0])
        let s = snapshot(cpu: 70, processes: [k])
        let r = SlowMacDiagnosis.request(question: "Perché è lento?", snapshot: s,
                                         findings: SlowMacDiagnosis.findings(for: s))
        #expect(r.prompt.contains("Attività di macOS (non vanno chiuse): kernel_task 300%"))
        #expect(r.prompt.contains("App aperte che usano più processore: nessuna"))
        #expect(r.prompt.contains("raffreddarlo"))
        #expect(r.instructions.contains("italiano"))
    }
}

@Suite struct IntentRouterTests {
    @Test(arguments: ["Perché il Mac è lento?", "il computer RALLENTA", "La ventola gira forte", "è tutto bloccato"])
    func recognisesSlowness(_ q: String) {
        #expect(IntentRouter.route(q) == .slowMac)
    }

    @Test func otherQuestionsAreNotYetSupported() {
        #expect(IntentRouter.route("Come faccio uno screenshot?") == .notYetSupported)
    }
}
