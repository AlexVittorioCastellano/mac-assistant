import Foundation

/// La risposta preparata per l'interfaccia.
public enum AssistantReply: Sendable {
    /// Risultato pronto: i `findings` si mostrano subito, la `aiRequest`
    /// si passa al provider per la spiegazione.
    case result(findings: [Finding], aiRequest: AIRequest)
    /// L'utente deve scegliere tra alcune opzioni (es. quale processo).
    /// Ogni opzione ha un'etichetta e la domanda da fare se viene scelta.
    case choices(message: String, options: [Choice])
    case message(String)
}

public struct Choice: Sendable, Equatable, Hashable {
    public var label: String
    public var question: String
    /// Bundle `.app` da cui prendere l'icona (l'app stessa o quella di cui
    /// il processo fa parte). `nil` = nessuna icona: l'interfaccia usa un simbolo.
    public var iconBundlePath: String?
    public var isSystem: Bool

    public init(label: String, question: String, iconBundlePath: String? = nil, isSystem: Bool = false) {
        self.label = label
        self.question = question
        self.iconBundlePath = iconBundlePath
        self.isSystem = isSystem
    }
}

/// Collega raccolta dati, funzioni e AI. Usato sia dall'app sia dalla CLI.
public struct Assistant: Sendable {
    public let provider: any AIProvider
    public let monitor: SystemMonitor

    public init(provider: any AIProvider = LocalProvider(), monitor: SystemMonitor = SystemMonitor()) {
        self.provider = provider
        self.monitor = monitor
    }

    public static let slowMacQuestion = "Perché il Mac è lento?"
    public static let processQuestion = "Cos'è questo processo?"

    public func prepare(question: String) async throws -> AssistantReply {
        let samples = try ProcessLister.list()
        let names = Array(Set(samples.map(\.name) + samples.map { ProcessLister.logicalName($0.name) }))

        switch IntentRouter.route(question, runningNames: names) {
        case .slowMac:
            let snapshot = try await monitor.snapshot()
            let findings = SlowMacDiagnosis.findings(for: snapshot)
            return .result(findings: findings,
                           aiRequest: SlowMacDiagnosis.request(question: question, snapshot: snapshot, findings: findings))

        case .process(nil):
            let options = ProcessExplainer.suggestions(from: samples).map {
                Choice(label: $0.name, question: "Cos'è «\($0.name)»?",
                       iconBundlePath: ProcessKind.outermostAppBundlePath(in: $0.path),
                       isSystem: $0.isSystem)
            }
            return .choices(message: "Quale processo vuoi capire? Ecco quelli che lavorano di più adesso. "
                                + "Puoi anche scrivere il nome, ad esempio: Cos'è mds_stores?",
                            options: options)

        case .process(let name?):
            guard let details = ProcessExplainer.find(name, in: samples) else {
                return .message(ProcessExplainer.notFoundMessage(for: name))
            }
            return .result(findings: ProcessExplainer.findings(for: details),
                           aiRequest: ProcessExplainer.request(question: question, details: details))

        case .notYetSupported:
            return .message("Per ora so rispondere a domande sulla lentezza del Mac e sui processi "
                            + "(es. «Cos'è mds_stores?»). Le altre funzioni arriveranno presto!")
        }
    }

    public func explain(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        provider.streamResponse(to: request)
    }
}
