import Testing
@testable import AssistenteCore

@Suite struct ProcessListerTests {
    static let psOutput = """
      1   0.0  12000 root     /sbin/launchd
    412  35.5 204800 alex     /Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)
    413  10.0 102400 alex     /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
      0 120.0   4096 root     launchd_fake
    500   5.0  50000 alex     /System/Library/PrivateFrameworks/CoreSuggestions.framework/Versions/A/Support/suggestd
    600   1.0  20000 alex     /Library/Application Support/Acme/AcmeUpdater
    """

    @Test func parsesPsOutputWithPathsAndSpaces() {
        let samples = ProcessLister.parse(Self.psOutput)
        #expect(samples.count == 6)
        #expect(samples[1].name == "Google Chrome Helper (Renderer)")
        #expect(samples[1].cpuPercent == 35.5)
        #expect(samples[1].residentBytes == 204800 * 1024)
        #expect(samples[3].name == "launchd_fake")
        #expect(ProcessLister.parse("7 1.0 100 alex .build/debug/MyApp").first?.name == "MyApp")
        #expect(samples[3].path == nil)

        let groups = ProcessLister.group(samples)
        let chrome = groups.first { $0.name == "Google Chrome" }
        #expect(chrome?.instanceCount == 2)
        #expect(chrome?.cpuPercent == 45.5)
        #expect(chrome?.isSystem == false)
        #expect(groups.first { $0.name == "launchd_fake" }?.isSystem == true)  // root senza percorso
        // Processo di sistema che gira come utente normale: va riconosciuto dal percorso.
        #expect(groups.first { $0.name == "suggestd" }?.isSystem == true)
    }
}

@Suite struct ProcessKindTests {
    @Test func classifiesByPath() {
        #expect(ProcessKind.classify(path: "/usr/libexec/rapportd", user: "alex") == .macOS)
        #expect(ProcessKind.classify(path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder", user: "alex") == .macOS)
        #expect(ProcessKind.classify(path: nil, user: "root") == .macOS)
        #expect(ProcessKind.classify(path: nil, user: "alex") == .unknown)
        #expect(ProcessKind.classify(path: "/Library/Application Support/Acme/AcmeUpdater", user: "root") == .background)
        #expect(ProcessKind.classify(path: "/usr/local/bin/node", user: "alex") == .background)
        #expect(ProcessKind.classify(path: "/Users/a/Library/Application Support/.com.apple.metadata.mds/mdworker_shared", user: "a") == .macOS)
    }

    @Test func appsInApplicationsFolders() {
        // Il bundle non esiste qui: il nome viene dal nome della cartella.
        #expect(ProcessKind.classify(path: "/Applications/Foo Bar.app/Contents/MacOS/Foo", user: "alex") == .app(name: "Foo Bar"))
        #expect(ProcessKind.classify(path: "/Applications/Foo Bar.app/Contents/Frameworks/X.framework/Helpers/Foo Helper.app/Contents/MacOS/Foo Helper", user: "alex")
                == .appComponent(appName: "Foo Bar"))
        // App di Apple in /System/Applications (es. Mail): si possono chiudere.
        #expect(ProcessKind.classify(path: "/System/Applications/Zzz.app/Contents/MacOS/Zzz", user: "alex") == .app(name: "Zzz"))
    }
}

@Suite struct SignatureTests {
    @Test func appleSystemBinaryIsSignedByApple() {
        #expect(ProcessKind.isSignedByAppleAsSystem("/usr/bin/true"))
        #expect(!ProcessKind.isSignedByAppleAsSystem("/percorso/inesistente"))
    }
}

@Suite struct ProcessExplainerTests {
    let samples = ProcessLister.parse(ProcessListerTests.psOutput)

    @Test func findsExactNameAndSaysSystemCannotBeClosed() throws {
        let d = try #require(ProcessExplainer.find("SUGGESTD", in: samples))
        #expect(d.group.name == "suggestd")
        #expect(d.group.kind == .macOS)
        let close = ProcessExplainer.findings(for: d).first { $0.id == "close" }
        #expect(close?.severity == .critical)
        #expect(d.note != nil)
    }

    @Test func findsAppIncludingHelpers() throws {
        let d = try #require(ProcessExplainer.find("Google Chrome", in: samples))
        #expect(d.group.instanceCount == 1)  // nome esatto: solo il processo principale
        let helper = try #require(ProcessExplainer.find("Google Chrome Helper (Renderer)", in: samples))
        #expect(helper.group.kind == .appComponent(appName: "Google Chrome"))
    }

    @Test func helperNameFindsComponentNotApp() throws {
        let d = try #require(ProcessExplainer.find("Google Chrome Helper", in: samples))
        #expect(d.group.kind == .appComponent(appName: "Google Chrome"))
    }

    @Test func knownButInvisibleProcessIsNotCalledInactive() {
        let m = ProcessExplainer.notFoundMessage(for: "kernel_task")
        #expect(m.contains("fa parte di macOS"))
        #expect(!m.contains("non è attivo"))
    }

    @Test func partialNameOnlyWhenUnambiguous() {
        #expect(ProcessExplainer.find("acme", in: samples)?.group.name == "AcmeUpdater")
        #expect(ProcessExplainer.find("doesnotexist", in: samples) == nil)
    }

    @Test func promptCarriesCodeVerdict() throws {
        let d = try #require(ProcessExplainer.find("trustd_fixture", in: samples + [
            ProcessSample(pid: 9, cpuPercent: 1, residentBytes: 1, user: "root", name: "trustd_fixture", path: "/usr/libexec/trustd_fixture")]))
        let r = ProcessExplainer.request(question: "Cos'è?", details: d)
        #expect(r.prompt.contains("Non chiuderlo"))
        #expect(r.prompt.contains("/usr/libexec/trustd_fixture"))  // niente nota: serve il percorso
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
        let advice = Finding.advice(from: SlowMacDiagnosis.findings(for: snapshot(cpu: 90, processes: [k])))
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
    let running = ["kernel_task", "mds_stores", "Google Chrome", "Mail", "bird"]

    @Test(arguments: ["Perché il Mac è lento?", "il computer RALLENTA", "La ventola gira forte", "è tutto bloccato"])
    func recognisesSlowness(_ q: String) {
        #expect(IntentRouter.route(q, runningNames: running) == .slowMac)
    }

    @Test func recognisesProcessQuestions() {
        #expect(IntentRouter.route("Cos'è mds_stores?", runningNames: running) == .process("mds_stores"))
        #expect(IntentRouter.route("cos’è KERNEL_TASK", runningNames: running) == .process("kernel_task"))
        #expect(IntentRouter.route("Posso chiudere Google Chrome?", runningNames: running) == .process("Google Chrome"))
        #expect(IntentRouter.route("Cos'è «pippo»?", runningNames: running) == .process("pippo"))
        #expect(IntentRouter.route("Cos'è Google Chrome Helper?", runningNames: running) == .process("Google Chrome Helper"))
        #expect(IntentRouter.route("Cosa fa xyzd?", runningNames: running) == .process("xyzd"))
        #expect(IntentRouter.route("Cos'è questo processo?", runningNames: running) == .process(nil))
    }

    @Test func processNamesNeedATriggerPhrase() {
        // "mail" senza "cos'è" ecc. non è una domanda su un processo.
        #expect(IntentRouter.route("Come mando una mail?", runningNames: running) == .notYetSupported)
        // Il nome deve essere una parola intera: "bird" non è in "birdwatching".
        #expect(IntentRouter.route("Cos'è birdwatching?", runningNames: running) == .process("birdwatching"))
    }

    @Test func otherQuestionsAreNotYetSupported() {
        #expect(IntentRouter.route("Come faccio uno screenshot?") == .notYetSupported)
    }
}
