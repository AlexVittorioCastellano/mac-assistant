import Foundation

/// La risposta preparata per l'interfaccia.
public enum AssistantReply: Sendable {
    /// Diagnosi pronta: i `findings` si mostrano subito, la `aiRequest`
    /// si passa al provider per la spiegazione.
    case diagnosis(findings: [Finding], aiRequest: AIRequest)
    case message(String)
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

    public func prepare(question: String) async throws -> AssistantReply {
        switch IntentRouter.route(question) {
        case .slowMac:
            let snapshot = try await monitor.snapshot()
            let findings = SlowMacDiagnosis.findings(for: snapshot)
            return .diagnosis(findings: findings,
                              aiRequest: SlowMacDiagnosis.request(question: question, snapshot: snapshot, findings: findings))
        case .notYetSupported:
            return .message("Per ora so rispondere solo a domande sulla lentezza del Mac. Le altre funzioni arriveranno presto!")
        }
    }

    public func explain(_ request: AIRequest) -> AsyncThrowingStream<String, Error> {
        provider.streamResponse(to: request)
    }
}
