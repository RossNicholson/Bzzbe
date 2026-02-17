#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel auto-compacts context when conversation nears model window")
func chatViewModelAutoCompactsNearContextWindow() async throws {
    let store = InMemoryConversationStore()
    let conversation = try await store.createConversation(title: "Compaction Test")

    for index in 0..<24 {
        let role: ConversationMessageRole = index.isMultiple(of: 2) ? .user : .assistant
        _ = try await store.addMessage(
            conversationID: conversation.id,
            role: role,
            content: "Turn \(index + 1): \(String(repeating: "long-context ", count: 30))"
        )
    }

    let client = CompactionCaptureInferenceClient()
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 512
    )
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: store,
        model: model
    )

    try await eventually {
        viewModel.activeConversationID == conversation.id && viewModel.messages.count == 24
    }

    viewModel.draft = "What should we do next?"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    let request = try #require(await client.lastRequest)
    #expect(request.messages.contains(where: { $0.content.contains("Compacted conversation summary") }))
    #expect(request.messages.count < 24)
    #expect(viewModel.commandFeedback?.contains("Auto-compacted") == true)
}

@MainActor
@Test("ChatViewModel does not auto-compact short conversations")
func chatViewModelSkipsAutoCompactionForShortContext() async throws {
    let store = InMemoryConversationStore()
    let conversation = try await store.createConversation(title: "Short Context")
    _ = try await store.addMessage(conversationID: conversation.id, role: .user, content: "Hello")
    _ = try await store.addMessage(conversationID: conversation.id, role: .assistant, content: "Hi there")

    let client = CompactionCaptureInferenceClient()
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 4_096
    )
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: store,
        model: model
    )

    try await eventually {
        viewModel.activeConversationID == conversation.id && viewModel.messages.count == 2
    }

    viewModel.draft = "Give me a quick summary."
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    let request = try #require(await client.lastRequest)
    #expect(!request.messages.contains(where: { $0.content.contains("Compacted conversation summary") }))
    #expect(viewModel.commandFeedback?.contains("Auto-compacted") != true)
}

private actor CompactionCaptureInferenceClient: InferenceClient {
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
