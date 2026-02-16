import Foundation

public enum InferenceRole: String, Sendable, Equatable {
    case system
    case user
    case assistant
}

public struct InferenceMessage: Sendable, Equatable {
    public let role: InferenceRole
    public let content: String

    public init(role: InferenceRole, content: String) {
        self.role = role
        self.content = content
    }
}

public struct InferenceModelDescriptor: Sendable, Equatable {
    public let identifier: String
    public let displayName: String
    public let contextWindow: Int

    public init(identifier: String, displayName: String, contextWindow: Int) {
        self.identifier = identifier
        self.displayName = displayName
        self.contextWindow = max(0, contextWindow)
    }
}

public struct InferenceRequest: Sendable, Equatable {
    public let model: InferenceModelDescriptor
    public let messages: [InferenceMessage]
    public let maxOutputTokens: Int
    public let temperature: Double

    public init(
        model: InferenceModelDescriptor,
        messages: [InferenceMessage],
        maxOutputTokens: Int = 512,
        temperature: Double = 0.7
    ) {
        self.model = model
        self.messages = messages
        self.maxOutputTokens = max(1, maxOutputTokens)
        self.temperature = max(0.0, min(2.0, temperature))
    }
}

public enum InferenceEvent: Sendable, Equatable {
    case started(modelIdentifier: String)
    case token(String)
    case completed
    case cancelled
}

public protocol InferenceClient: Sendable {
    func loadModel(_ model: InferenceModelDescriptor) async throws
    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error>
    func cancelCurrentRequest() async
}

public actor MockInferenceClient: InferenceClient {
    private var currentTask: Task<Void, Never>?
    private var currentContinuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation?

    public init() {}

    public func loadModel(_ model: InferenceModelDescriptor) async throws {
        guard !model.identifier.isEmpty else {
            throw MockInferenceError.emptyModelIdentifier
        }
    }

    public func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            currentContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.cancelCurrentRequest()
                }
            }

            currentTask = Task {
                continuation.yield(.started(modelIdentifier: request.model.identifier))

                let prompt = request.messages.map(\.content).joined(separator: " ")
                let response = "Stub response for: \(prompt)"

                for token in response.split(separator: " ") {
                    if Task.isCancelled {
                        continuation.yield(.cancelled)
                        continuation.finish()
                        return
                    }

                    continuation.yield(.token(String(token) + " "))
                    try? await Task.sleep(for: .milliseconds(25))
                }

                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    public func cancelCurrentRequest() async {
        currentTask?.cancel()
        currentTask = nil
        currentContinuation?.yield(.cancelled)
        currentContinuation?.finish()
        currentContinuation = nil
    }
}

public enum MockInferenceError: Error {
    case emptyModelIdentifier
}
