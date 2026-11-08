import AppKit
import AssistenteCore
import SwiftUI

@MainActor
enum DemoScreenshots {
    static func runIfRequested() {
        guard let folder = ProcessInfo.processInfo.environment["ASSISTENTE_SCREENSHOTS"] else { return }
        Task {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            for code in ["it", "en"] {
                L.override = code
                for (name, make) in scenarios {
                    let model = AssistantViewModel()
                    await make(model)
                    for dark in [false, true] {
                        render(model, to: "\(folder)/\(name)-\(code)\(dark ? "-scuro" : "").png", dark: dark)
                    }
                }
            }
            exit(0)
        }
    }

    nonisolated static let assistant = Assistant()

    static func explain(_ request: AIRequest?) async -> String {
        guard let request else { return "" }
        return (try? await assistant.provider.respond(to: request)) ?? ""
    }

    nonisolated static let demoSnapshot = SystemSnapshot(
        cpuUsagePercent: 18, coreCount: 10,
        memory: MemoryInfo(totalBytes: 16 << 30, usedBytes: 9 << 30, cachedBytes: 3 << 30, compressedBytes: 1 << 30,
                           swapUsedBytes: 0, pressure: .normal),
        thermal: .nominal, uptime: 3 * 86_400, processes: [])

    static let scenarios: [(String, @MainActor (AssistantViewModel) async -> Void)] = [
        ("controllo", { m in
            m.question = Assistant.healthQuestion
            let status = MacStatus(fileVaultOn: true, firewallOn: false, gatekeeperOn: true, sipOn: true,
                                   backup: .notConfigured, automaticUpdatesOn: true, pendingUpdates: 0,
                                   battery: BatteryHealth(healthPercent: 92, cycleCount: 214))
            m.findings = HealthCheck.findings(for: .init(snapshot: demoSnapshot, disk: (494 << 30, 212 << 30),
                                                         status: status, suspicious: 0))
        }),
        ("spazio", { m in
            m.question = Assistant.diskQuestion
            let usage = DiskUsage(totalBytes: 494 << 30, freeBytes: 212 << 30, purgeableBytes: 6 << 30, macOSBytes: 22 << 30,
                                  items: [DiskItem(category: .appleAI, bytes: 35 << 30),
                                          DiskItem(category: .applications, bytes: 41 << 30, path: "/Applications"),
                                          DiskItem(category: .pictures, bytes: 88 << 30),
                                          DiskItem(category: .downloads, bytes: 19 << 30),
                                          DiskItem(category: .caches, bytes: 7 << 30),
                                          DiskItem(category: .appData, bytes: 12 << 30)],
                                  localSnapshotCount: 0)
            m.findings = DiskSpaceAnalysis.findings(for: usage)
            m.chart = DiskSpaceAnalysis.chart(for: usage)
            m.answer = await explain(DiskSpaceAnalysis.request(question: m.question, usage: usage))
        }),
        ("chat", { m in
            let question = L.current.code == "it" ? "Come faccio uno screenshot di una finestra?" : "How do I take a screenshot of one window?"
            let guides = MacHelpChat.guides(for: question)
            let session = assistant.makeChatSession()
            let answer = (try? await collectStream(session.send(MacHelpChat.prompt(for: question, guides: guides)))) ?? ""
            m.messages = [ChatMessage(role: .user, text: question),
                          ChatMessage(role: .assistant, text: answer, basedOnGuide: !guides.isEmpty)]
        }),
        ("messaggio", { m in
            m.question = Assistant.messageQuestion
            let text = L.current.code == "it"
                ? "ATTENZIONE! Il tuo Mac è infetto da 3 virus. Chiama subito il supporto Apple al numero verde 800 000 000"
                : "WARNING! Your Mac is infected with 3 viruses. Call Apple Support now at 1-800-000-0000"
            m.findings = MessageExplainer.findings(for: text)
            m.answer = await explain(MessageExplainer.request(for: text))
        }),
        ("pulizia", { m in
            m.question = Assistant.cleanupQuestion
            let it = L.current.code == "it"
            m.cleanupItems = [
                CleanupItem(name: "Installer-Videochiamate.dmg", path: "/Users/demo/Downloads/Installer-Videochiamate.dmg",
                            bytes: 312 << 20, reason: .installer, preselected: true),
                CleanupItem(name: it ? "Vacanze-2023.mov" : "Holiday-2023.mov", path: "/Users/demo/Movies/Holiday-2023.mov",
                            bytes: 4 << 30, reason: .large, preselected: false),
                CleanupItem(name: it ? "Catalogo-vecchio.pdf" : "Old-catalog.pdf", path: "/Users/demo/Downloads/Old-catalog.pdf",
                            bytes: 46 << 20, reason: .unusedDownload(days: 210), preselected: false),
            ]
            m.cleanupSelected = ["/Users/demo/Downloads/Installer-Videochiamate.dmg"]
        }),
    ]

    static func collectStream(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var last = ""
        for try await partial in stream { last = partial }
        return last
    }

    static func render(_ model: AssistantViewModel, to path: String, dark: Bool) {
        let root = ContentView(model: model)
            .padding(.top, 6)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 900),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
