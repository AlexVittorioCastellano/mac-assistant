import Foundation
import FoundationModels

public struct LocalProvider: AIProvider {
    public init() {}

    public var displayName: String { L.t("error.provider.name") }
    public var isOnDevice: Bool { true }

    public var availability: ProviderAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.supportsLocale(L.locale) else {
                return .unavailable(L.t("error.ai.noLanguage"))
            }
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(L.t("error.ai.notEligible"))
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(L.t("error.ai.notEnabled"))
        case .unavailable(.modelNotReady):
            return .unavailable(L.t("error.ai.notReady"))
        case .unavailable:
            return .unavailable(L.t("error.ai.unavailable"))
        }
    }

    public func streamResponse(to request: AIRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
                    let session = LanguageModelSession(model: model, instructions: request.instructions)

                    let options = GenerationOptions(temperature: 0.3)
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.friendly(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func makeChatSession(instructions: String) -> any AIChatSession {
        LocalChatSession(instructions: instructions)
    }

    static func makeSession(instructions: String) -> LanguageModelSession {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        return LanguageModelSession(model: model, instructions: instructions)
    }

    static func friendly(_ error: Error) -> Error {
        if error is SystemLanguageModel.Error {
            return AIError(L.t("error.ai.notReadyShort"))
        }
        guard let error = error as? LanguageModelError else { return error }
        switch error {
        case .contextSizeExceeded:
            return AIError(L.t("error.ai.tooLong"))
        case .guardrailViolation, .refusal:
            return AIError(L.t("error.ai.refused"))
        case .unsupportedLanguageOrLocale:
            return AIError(L.t("error.ai.unsupportedLanguage"))
        case .rateLimited:
            return AIError(L.t("error.ai.busy"))
        case .timeout:
            return AIError(L.t("error.ai.timeout"))
        default:
            return AIError(L.t("error.ai.failed"))
        }
    }
}

actor LocalChatSession: AIChatSession {
    private let instructions: String
    private var session: LanguageModelSession

    init(instructions: String) {
        self.instructions = instructions
        self.session = LocalProvider.makeSession(instructions: instructions)
    }

    nonisolated func send(_ prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.run(prompt, continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ prompt: String, _ continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        do {
            let options = GenerationOptions(samplingMode: .greedy)
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                continuation.yield(snapshot.content)
            }
            continuation.finish()
        } catch LanguageModelError.contextSizeExceeded {
            session = LocalProvider.makeSession(instructions: instructions)
            continuation.finish(throwing: AIError(
                L.t("error.ai.chatTooLong")))
        } catch {
            continuation.finish(throwing: LocalProvider.friendly(error))
        }
    }
}
