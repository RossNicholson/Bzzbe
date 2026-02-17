#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel injects enabled personal memory as system context")
func chatViewModelInjectsMemoryContext() async throws {
    let client = MemoryCaptureInferenceClient()
    let memory = StubMemoryContextProvider(
        context: MemoryContext(
            isEnabled: true,
            content: "Preferred style: concise bullet points."
        )
    )

    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore(),
        memoryContextProvider: memory
    )

    viewModel.draft = "Summarize this article"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    let request = try #require(await client.lastRequest)
    let systemMessage = try #require(request.messages.first)
    #expect(systemMessage.role == .system)
    #expect(systemMessage.content.contains("Preferred style"))
    #expect(request.messages.contains(where: { $0.role == .user && $0.content == "Summarize this article" }))
}

@MainActor
@Test("ChatViewModel skips memory context when disabled")
func chatViewModelSkipsMemoryWhenDisabled() async throws {
    let client = MemoryCaptureInferenceClient()
    let memory = StubMemoryContextProvider(
        context: MemoryContext(
            isEnabled: false,
            content: "Should not be injected"
        )
    )

    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore(),
        memoryContextProvider: memory
    )

    viewModel.draft = "Hello"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    let request = try #require(await client.lastRequest)
    #expect(!request.messages.contains(where: { $0.role == .system && $0.content.contains("Should not be injected") }))
}

private struct StubMemoryContextProvider: MemoryContextProviding {
    let context: MemoryContext

    func loadContext() -> MemoryContext {
        context
    }
}

private actor MemoryCaptureInferenceClient: InferenceClient {
    private(set) var lastRequest: InferenceRequest?

    func loadModel(_ model: InferenceModelDescriptor) async throws {}

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(modelIdentifier: request.model.identifier))
            continuation.yield(.token("ok"))
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    func cancelCurrentRequest() async {}
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @MainActor @escaping () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    throw PollingTimeoutError()
}

private struct PollingTimeoutError: Error {}
#endif
