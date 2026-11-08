import Foundation

/// La risposta preparata per l'interfaccia.
public enum AssistantReply: Sendable {
    /// Risultato pronto: i `findings` si mostrano subito, la `aiRequest`
    /// si passa al provider per la spiegazione.
    case result(findings: [Finding], aiRequest: AIRequest, chart: SegmentedChart? = nil)
    /// L'utente deve scegliere tra alcune opzioni (es. quale processo).
    /// Ogni opzione ha un'etichetta e la domanda da fare se viene scelta.
    case choices(message: String, options: [Choice])
    case message(String)
    /// Chat libera: `prompt` va inviato alla conversazione in corso
    /// (vedi `makeChatSession`), così il modello ricorda i messaggi precedenti.
    /// `guides` sono le guide verificate usate (per la rete di sicurezza).
    case chat(prompt: String, guides: [String])
}

public struct Choice: Sendable, Equatable, Hashable {
    public var label: String
    public var question: String
    /// File o cartella da cui prendere l'icona (es. l'app di cui il processo
    /// fa parte). Se manca, si usa `symbol`.
    public var iconPath: String?
    public var symbol: String

    public init(label: String, question: String, iconPath: String? = nil, symbol: String = "app.dashed") {
        self.label = label
        self.question = question
        self.iconPath = iconPath
        self.symbol = symbol
    }
}

/// Collega raccolta dati, funzioni e AI. Usato sia dall'app sia dalla CLI.
public struct Assistant: Sendable {
    public let provider: any AIProvider
    public let monitor: SystemMonitor
    public let disk: DiskMonitor

    public init(provider: any AIProvider = LocalProvider(), monitor: SystemMonitor = SystemMonitor(),
                disk: DiskMonitor = DiskMonitor()) {
        self.provider = provider
        self.monitor = monitor
        self.disk = disk
    }

    public static let slowMacQuestion = "Perché il Mac è lento?"
    public static let processQuestion = "Cos'è questo processo?"
    public static let diskQuestion = "Dove è finito lo spazio?"

    /// - Parameter conversationGuides: guide usate nel turno precedente della
    ///   chat. Una domanda di seguito ("E se non compare?") senza guide proprie
    ///   le eredita, così il modello resta ancorato alle informazioni corrette.
    public func prepare(question: String, conversationGuides: [String] = []) async throws -> AssistantReply {
        let samples = try ProcessLister.list()
        let names = Array(Set(samples.map(\.name) + samples.map { ProcessLister.logicalName($0.name) }))

        var intent = IntentRouter.route(question, runningNames: names)
        // "Come chiudo un programma bloccato?" contiene "bloccato" (lentezza), ma
        // è una domanda pratica con una guida pronta: risponde la chat.
        if intent == .slowMac || intent == .diskSpace,
           IntentRouter.isHowTo(question), !MacHelpChat.guides(for: question).isEmpty {
            intent = .chat
        }

        switch intent {
        case .slowMac:
            let snapshot = try await monitor.snapshot()
            let findings = SlowMacDiagnosis.findings(for: snapshot)
            return .result(findings: findings,
                           aiRequest: SlowMacDiagnosis.request(question: question, snapshot: snapshot, findings: findings))

        case .diskSpace:
            let usage = await disk.usage()
            return .result(findings: DiskSpaceAnalysis.findings(for: usage),
                           aiRequest: DiskSpaceAnalysis.request(question: question, usage: usage),
                           chart: DiskSpaceAnalysis.chart(for: usage))

        case .process(nil):
            let options = ProcessExplainer.suggestions(from: samples).map {
                Choice(label: $0.name, question: "Cos'è «\($0.name)»?",
                       iconPath: ProcessKind.outermostAppBundlePath(in: $0.path),
                       symbol: ProcessExplainer.symbol(for: $0))
            }
            return .choices(message: "Quale processo vuoi capire? Ecco quelli che lavorano di più adesso. "
                                + "Puoi anche scrivere il nome, ad esempio: Cos'è mds_stores?",
                            options: options)

        case .process(let name?):
            // "Cos'è AirDrop?" riguarda una funzione del Mac, non un processo: se
            // la parola "processo" non c'è e il nome non corrisponde esattamente
            // a un processo (o a uno noto), risponde la chat.
            let saysProcess = IntentRouter.normalize(question).contains("process")
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

    /// Nuova conversazione per la chat libera.
    public func makeChatSession() -> any AIChatSession {
        provider.makeChatSession(instructions: MacHelpChat.instructions)
    }

    public func explain(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        provider.streamResponse(to: request)
    }
}
