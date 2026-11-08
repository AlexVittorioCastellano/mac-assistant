import Foundation
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
        #expect(ProcessExplainer.find("acme", in: samples)?.isExactMatch == false)
        #expect(ProcessExplainer.find("AcmeUpdater", in: samples)?.isExactMatch == true)
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
        #expect(IntentRouter.route("Come mando una mail?", runningNames: running) == .chat)
        // Il nome deve essere una parola intera: "bird" non è in "birdwatching".
        #expect(IntentRouter.route("Cos'è birdwatching?", runningNames: running) == .process("birdwatching"))
    }

    @Test(arguments: ["Dove è finito lo spazio?", "Il disco è pieno", "Cosa sono i Dati di sistema?",
                      "Ho la memoria piena", "Cos'è dati di sistema?", "Quanto spazio occupano gli snapshot?"])
    func recognisesDiskSpace(_ q: String) {
        #expect(IntentRouter.route(q, runningNames: running) == .diskSpace)
    }

    @Test func keywordsMatchOnlyAtWordStart() {
        // "ingrandisco" non è "disco", "programma" non è "RAM".
        #expect(IntentRouter.route("Come ingrandisco le scritte?", runningNames: running) == .chat)
        #expect(IntentRouter.route("Come tolgo un programma?", runningNames: running) == .chat)
        #expect(IntentRouter.route("Il computer è lentissimo", runningNames: running) == .slowMac)
    }

    @Test func slownessWinsOverDiskWords() {
        #expect(IntentRouter.route("Il disco è lento", runningNames: running) == .slowMac)
        #expect(IntentRouter.route("Quale app occupa più RAM?", runningNames: running) == .slowMac)
    }

    @Test func followUpDetection() {
        #expect(IntentRouter.isFollowUp("E se il mio iPhone non compare?"))
        #expect(IntentRouter.isFollowUp("Ma dove lo trovo?"))
        #expect(IntentRouter.isFollowUp("Non funziona"))
        #expect(!IntentRouter.isFollowUp("Come creo un nuovo utente?"))
        #expect(!IntentRouter.isFollowUp("Emoji: come le scrivo?"))
    }

    @Test func otherQuestionsGoToChat() {
        #expect(IntentRouter.route("Come faccio uno screenshot?") == .chat)
        #expect(IntentRouter.route("Come faccio un'istantanea dello schermo?") == .chat)
        #expect(IntentRouter.route("Come cambio lo sfondo?") == .chat)
    }
}

@Suite struct DiskSpaceTests {
    let gb: UInt64 = 1 << 30

    func usage(free: UInt64 = 200 << 30, snapshots: Int = 0) -> DiskUsage {
        DiskUsage(totalBytes: 500 << 30, freeBytes: free, purgeableBytes: 3 << 30, macOSBytes: 20 << 30,
                  items: [DiskItem(category: .appleAI, bytes: 25 << 30),
                          DiskItem(category: .downloads, bytes: 7 << 30, path: "/Users/x/Downloads"),
                          DiskItem(category: .caches, bytes: 2 << 30),
                          DiskItem(category: .trash, bytes: 100 << 20)],
                  localSnapshotCount: snapshots)
    }

    @Test func otherIsWhatIsLeft() {
        let u = usage()
        // usati 300 GB - macOS 20 - voci (25 + 7 + 2 + 0,1) = 245,9 GB
        #expect(u.otherBytes == (300 << 30) - (20 << 30) - (34 << 30) - (100 << 20))
    }

    @Test func findingsAreSortedAndHaveSafeAdvice() {
        let f = DiskSpaceAnalysis.findings(for: usage())
        #expect(f.first?.id == "free")
        #expect(f.first?.severity == .ok)
        let ids = f.map(\.id)
        // "altro" (245 GB) prima dei modelli AI (25 GB), poi macOS, Download…
        #expect(ids.firstIndex(of: "other")! < ids.firstIndex(of: "appleAI")!)
        #expect(ids.firstIndex(of: "appleAI")! < ids.firstIndex(of: "downloads")!)
        // Il Cestino (piccolo) finisce in "Il resto".
        #expect(!ids.contains("trash"))
        #expect(ids.contains("rest"))
        #expect(f.contains { $0.id == "systemdata" })
        // Nessun consiglio dice di cancellare qualcosa al posto dell'utente.
        #expect(!Finding.advice(from: f).contains { $0.localizedCaseInsensitiveContains("ho cancellato") })
    }

    @Test func chartSplitsUsedSpaceAndMatchesList() {
        let u = usage()
        let chart = DiskSpaceAnalysis.chart(for: u)
        // 5 voci colorate + il resto; lo spazio libero non è un blocco.
        #expect(chart.segments.count == 6)
        #expect(chart.segments.map(\.swatch).prefix(5) == [.series(0), .series(1), .series(2), .series(3), .series(4)])
        #expect(chart.segments.last?.swatch == .rest)
        #expect(chart.totalBytes == u.usedBytes)
        #expect(chart.capacityBytes == u.totalBytes)
        #expect(chart.capacitySummary == "Usati 300,0 GB su 500,0 GB (60%)")
        // Le righe dell'elenco usano gli stessi colori nello stesso ordine.
        let rows = DiskSpaceAnalysis.findings(for: u).compactMap(\.swatch)
        #expect(rows == chart.segments.map(\.swatch))
    }

    @Test func lowSpaceIsCriticalAndGivesCleanupAdvice() {
        let f = DiskSpaceAnalysis.findings(for: usage(free: 5 << 30))
        #expect(f.first?.severity == .critical)
        #expect(Finding.advice(from: f).contains { $0.contains("Download") })
    }

    @Test func plentyOfSpaceGivesNoCleanupAdvice() {
        let advice = Finding.advice(from: DiskSpaceAnalysis.findings(for: usage()))
        #expect(advice == ["Hai ancora molto spazio libero: non serve liberarne adesso."])
    }

    @Test func snapshotsAreMentioned() {
        #expect(DiskSpaceAnalysis.findings(for: usage(snapshots: 3)).contains { $0.id == "snapshots" })
    }

    @Test func parsesBootContainer() throws {
        let containers: [[String: Any]] = [
            ["CapacityCeiling": NSNumber(value: 5 << 30), "CapacityFree": NSNumber(value: 4 << 30),
             "Volumes": [["Roles": ["Recovery"], "CapacityInUse": NSNumber(value: 1 << 30)]]],
            ["CapacityCeiling": NSNumber(value: 1000 << 30), "CapacityFree": NSNumber(value: 800 << 30),
             "Volumes": [["Roles": ["System"], "CapacityInUse": NSNumber(value: 12 << 30)],
                         ["Roles": ["Preboot"], "CapacityInUse": NSNumber(value: 9 << 30)],
                         ["Roles": ["Data"], "CapacityInUse": NSNumber(value: 80 << 30)]]],
        ]
        let c = try #require(DiskMonitor.parseContainers(containers))
        #expect(c.total == 1000 << 30)
        #expect(c.macOS == 21 << 30)
    }
}

@Suite struct MacHelpChatTests {
    @Test func addsVerifiedGuideWhenRelevant() {
        let p = MacHelpChat.prompt(for: "Come faccio uno SCREENSHOT?")
        #expect(p.contains("Guida verificata"))
        #expect(p.contains("⌘⇧4"))
    }

    @Test func noGuideForUnknownTopicsAsksForCaution() {
        let p = MacHelpChat.prompt(for: "Come creo un nuovo utente?")
        #expect(MacHelpChat.guides(for: "Come creo un nuovo utente?").isEmpty)
        #expect(p.contains("Non inventare"))
    }

    @Test(arguments: ["Come mando un file al mio iPhone?", "come passo le foto sull'iphone", "Posso inviare un video all'iPad?"])
    func combinedKeywordsFindAirDrop(_ q: String) {
        #expect(MacHelpChat.guides(for: q).first?.hasPrefix("AirDrop") == true)
    }

    @Test func atMostTwoGuides() {
        let p = MacHelpChat.prompt(for: "screenshot, emoji, stampare e bluetooth")
        #expect(p.components(separatedBy: "\n- ").count == 3)
    }

    @Test func safetyNetCatchesWrongShortcuts() {
        let guides = MacHelpChat.guides(for: "screenshot")
        #expect(MacHelpChat.shortcuts(in: "Premi **⌘⇧3**, poi ⌥⌘Esc.") == ["⌘⇧3", "⌥⌘Esc"])
        #expect(MacHelpChat.shortcuts(in: "Nel Finder premi ⌘⇧.") == ["⌘⇧."])
        #expect(MacHelpChat.shortcuts(in: "Tieni premuto il tasto ⌘.") == ["⌘"])
        #expect(!MacHelpChat.answerNeedsGuide("2. Premi ⌘⇧.", guides: MacHelpChat.guides(for: "file nascosti")))
        // Corretta: nessun riquadro.
        #expect(!MacHelpChat.answerNeedsGuide("1. Premi **⌘⇧3** per tutto lo schermo.", guides: guides))
        // Manca ⇧: serve il riquadro.
        #expect(MacHelpChat.answerNeedsGuide("1. Premi il tasto ⌘ e il tasto 3.", guides: guides))
        #expect(MacHelpChat.answerNeedsGuide("Premi ⌘3.", guides: guides))
        // Senza guide non si può verificare nulla.
        #expect(!MacHelpChat.answerNeedsGuide("Premi ⌘3.", guides: []))
    }

    @Test func spotlightShortcutFromInstructionsIsAllowed() {
        let guides = MacHelpChat.guides(for: "modalita scura")
        #expect(!MacHelpChat.answerNeedsGuide("Cerca «Aspetto» con Spotlight (⌘ Spazio).", guides: guides))
    }

    @Test func instructionsNameTheMacOSVersion() {
        #expect(MacHelpChat.instructions.contains("macOS "))
    }
}

@Suite struct HealthCheckTests {
    func input(status: MacStatus, free: UInt64 = 300 << 30, cpu: Double = 10, uptimeDays: Double = 1) -> HealthCheck.Input {
        let snap = SystemSnapshot(
            cpuUsagePercent: cpu, coreCount: 8,
            memory: MemoryInfo(totalBytes: 16 << 30, usedBytes: 8 << 30, cachedBytes: 0, compressedBytes: 0,
                               swapUsedBytes: 0, pressure: .normal),
            thermal: .nominal, uptime: uptimeDays * 86_400, processes: [])
        return HealthCheck.Input(snapshot: snap, disk: (500 << 30, free), status: status)
    }

    @Test func allGoodIsGreen() {
        let status = MacStatus(fileVaultOn: true, firewallOn: true, gatekeeperOn: true, sipOn: true,
                               backup: .configured(lastBackup: Date()), automaticUpdatesOn: true, pendingUpdates: 0,
                               battery: BatteryHealth(healthPercent: 95, cycleCount: 100))
        let f = HealthCheck.findings(for: input(status: status))
        #expect(f.first?.title == "Il tuo Mac sta bene")
        #expect(f.first?.severity == .ok)
        #expect(f.dropFirst().allSatisfy { $0.severity == .ok })
    }

    @Test func problemsAreCountedAndListedFirst() {
        let status = MacStatus(fileVaultOn: false, firewallOn: false, gatekeeperOn: false, sipOn: true,
                               backup: .notConfigured, automaticUpdatesOn: true,
                               battery: BatteryHealth(healthPercent: 72, cycleCount: 900))
        let f = HealthCheck.findings(for: input(status: status, free: 20 << 30))
        // FileVault, Gatekeeper, backup, batteria, spazio = 5; il firewall spento è solo un'informazione.
        #expect(f.first?.title == "Ci sono 5 cose da sistemare")
        #expect(f.first?.severity == .critical)
        // Le voci critiche per prime, nell'ordine fisso (spazio prima di Gatekeeper).
        #expect(f[1].id == "disk")
        #expect(f[2].id == "gatekeeper")
        #expect(f.first { $0.id == "firewall" }?.severity == .info)
    }

    @Test func oldBackupIsAWarning() {
        let tenDaysAgo = Date().addingTimeInterval(-10 * 86_400)
        let f = HealthCheck.findings(for: input(status: MacStatus(backup: .configured(lastBackup: tenDaysAgo))))
        #expect(f.first { $0.id == "backup" }?.title == "Ultimo backup 10 giorni fa")
    }

    @Test func unknownValuesAreSkippedNotGuessed() {
        let f = HealthCheck.findings(for: input(status: MacStatus()))
        #expect(!f.contains { $0.id == "filevault" || $0.id == "sip" || $0.id == "battery" })
    }

    @Test func parsesAppleSiliconBatteryPlist() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><array><dict>
        <key>CycleCount</key><integer>3</integer><key>MaxCapacity</key><integer>100</integer>
        <key>BatteryData</key><dict><key>DesignCapacity</key><integer>8579</integer>
        <key>AppleRawMaxCapacity</key><integer>6863</integer></dict>
        </dict></array></plist>
        """
        let b = try #require(MacStatusMonitor.parseBattery(plist))
        #expect(b.healthPercent == 80)
        #expect(b.cycleCount == 3)
        #expect(MacStatusMonitor.parseBattery("") == nil)  // Mac senza batteria
    }

    @Test func routesHealthQuestions() {
        #expect(IntentRouter.route("Controlla il mio Mac") == .healthCheck)
        #expect(IntentRouter.route("Il mio Mac sta bene?") == .healthCheck)
        #expect(IntentRouter.route("Il Mac è sicuro?") == .healthCheck)
        // "Centro di Controllo" non è un controllo generale.
        #expect(IntentRouter.route("Come apro il Centro di Controllo?") == .chat)
    }
}
