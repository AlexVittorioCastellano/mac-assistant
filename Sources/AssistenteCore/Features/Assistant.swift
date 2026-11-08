import Foundation

public enum AssistantReply: Sendable {
    case result(findings: [Finding], aiRequest: AIRequest?, chart: SegmentedChart? = nil)

    case choices(message: String, options: [Choice])
    case message(String)

    case cleanup([CleanupItem])

    case chat(prompt: String, guides: [String])
}

public struct Choice: Sendable, Equatable, Hashable {
    public var label: String
    public var question: String

    public var iconPath: String?
    public var symbol: String

    public init(label: String, question: String, iconPath: String? = nil, symbol: String = "app.dashed") {
        self.label = label
        self.question = question
        self.iconPath = iconPath
        self.symbol = symbol
    }
}

public struct Assistant: Sendable {
    public let provider: any AIProvider
    public let monitor: SystemMonitor
    public let disk: DiskMonitor
    public let status: MacStatusMonitor

    public init(provider: any AIProvider = LocalProvider(), monitor: SystemMonitor = SystemMonitor(),
                disk: DiskMonitor = DiskMonitor(), status: MacStatusMonitor = MacStatusMonitor()) {
        self.provider = provider
        self.monitor = monitor
        self.disk = disk
        self.status = status
    }

    public static var slowMacQuestion: String { L.t("question.slow") }
    public static var processQuestion: String { L.t("question.process") }
    public static var diskQuestion: String { L.t("question.disk") }
    public static var healthQuestion: String { L.t("question.health") }
    public static var securityQuestion: String { L.t("question.security") }
    public static var cleanupQuestion: String { L.t("question.cleanup") }

    public func prepare(question: String, conversationGuides: [String] = []) async throws -> AssistantReply {
        let samples = try ProcessLister.list()
        let names = Array(Set(samples.map(\.name) + samples.map { ProcessLister.logicalName($0.name) }))

        var intent = IntentRouter.route(question, runningNames: names)

        if [.slowMac, .diskSpace, .healthCheck, .securityScan, .cleanup].contains(intent),
           IntentRouter.isHowTo(question), !MacHelpChat.guides(for: question).isEmpty {
            intent = .chat
        }

        switch intent {
        case .slowMac:
            let snapshot = try await monitor.snapshot()
            let findings = SlowMacDiagnosis.findings(for: snapshot)
            return .result(findings: findings,
                           aiRequest: SlowMacDiagnosis.request(question: question, snapshot: snapshot, findings: findings))

        case .cleanup:
            return .cleanup(await Cleanup.candidates())

        case .securityScan:
            let result = await SecurityScanner().scan()
            return .result(findings: SecurityScan.findings(for: result), aiRequest: nil)

        case .healthCheck:
            async let snapshot = monitor.snapshot()
            async let macStatus = status.status()
            async let scan = SecurityScanner().scan()
            let capacity = DiskMonitor.volumeCapacity()
            let input = HealthCheck.Input(snapshot: try await snapshot, disk: (capacity.total, capacity.free),
                                          status: await macStatus,
                                          suspicious: SecurityScan.problemCount(await scan))
            return .result(findings: HealthCheck.findings(for: input), aiRequest: nil)

        case .diskSpace:
            let usage = await disk.usage()
            return .result(findings: DiskSpaceAnalysis.findings(for: usage),
                           aiRequest: DiskSpaceAnalysis.request(question: question, usage: usage),
                           chart: DiskSpaceAnalysis.chart(for: usage))

        case .process(nil):
            let options = ProcessExplainer.suggestions(from: samples).map {
                Choice(label: $0.name, question: L.t("question.processNamed", $0.name),
                       iconPath: ProcessKind.outermostAppBundlePath(in: $0.path),
                       symbol: ProcessExplainer.symbol(for: $0))
            }
            return .choices(message: L.t("process.choose"),
                            options: options)

        case .process(let name?):

            let saysProcess = IntentRouter.normalize(question).contains(L.t("router.processWord"))
            let details = ProcessExplainer.find(name, in: samples)
            if !saysProcess && KnownProcesses.note(for: name) == nil && details?.isExactMatch != true {
                return chatReply(question, conversationGuides)
            }
            guard let details else {
                return .message(ProcessExplainer.notFoundMessage(for: name))
            }
            return .result(findings: ProcessExplainer.findings(for: details),
                           aiRequest: ProcessExplainer.request(question: question, details: details))

        case .chat:
            if case .unavailable(let reason) = provider.availability {
                return .message(reason)
            }
            return chatReply(question, conversationGuides)
        }
    }

    private func chatReply(_ question: String, _ conversationGuides: [String]) -> AssistantReply {
        var guides = MacHelpChat.guides(for: question)
        if guides.isEmpty && IntentRouter.isFollowUp(question) { guides = conversationGuides }
        return .chat(prompt: MacHelpChat.prompt(for: question, guides: guides), guides: guides)
    }

    public static var messageQuestion: String { L.t("question.message") }

    public func explainMessage(_ text: String) -> AssistantReply {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            return .message(L.t("message.empty"))
        }
        return .result(findings: MessageExplainer.findings(for: t), aiRequest: MessageExplainer.request(for: t))
    }

    public func explainMessage(imageData: Data) async throws -> AssistantReply {
        explainMessage(try await TextRecognizer.text(inImageData: imageData))
    }

    public func makeChatSession() -> any AIChatSession {
        provider.makeChatSession(instructions: MacHelpChat.instructions)
    }

    public func explain(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        provider.streamResponse(to: request)
    }
}
