import Foundation

public struct AIRequest: Sendable, Equatable {
    public var instructions: String
    public var prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

public enum ProviderAvailability: Sendable, Equatable {
    case available

    case unavailable(String)
}

public struct AIError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public protocol AIProvider: Sendable {
    var displayName: String { get }

    var isOnDevice: Bool { get }

    var availability: ProviderAvailability { get }

    func streamResponse(to request: AIRequest) -> AsyncThrowingStream<String, Error>

    func makeChatSession(instructions: String) -> any AIChatSession
}

public protocol AIChatSession: Sendable {
    func send(_ prompt: String) -> AsyncThrowingStream<String, Error>
}

extension AIProvider {
    public func respond(to request: AIRequest) async throws -> String {
        var last = ""
        for try await partial in streamResponse(to: request) { last = partial }
        return last
    }
}
