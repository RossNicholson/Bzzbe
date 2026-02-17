#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel retries with fallback model when primary model is unavailable")
func chatViewModelRetriesWithFallbackModel() async throws {
    let primary = InferenceModelDescriptor(
        identifier: "primary-model",
        displayName: "Primary",
        contextWindow: 32_768
    )
    let fallback = InferenceModelDescriptor(
        identifier: "fallback-model",
        displayName: "Fallback",
        contextWindow: 32_768
    )
    let client = FailoverInferenceClient(unavailableModelIDs: [primary.identifier])
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore(),
        fallbackModels: [fallback],
        model: primary
    )

    viewModel.draft = "hello"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    #expect(viewModel.model.identifier == fallback.identifier)
    #expect(viewModel.commandFeedback?.contains("Model failover") == true)
    #expect(await client.loadModelIDs == [primary.identifier, fallback.identifier])
}

@MainActor
@Test("ChatViewModel surfaces normal recovery when no fallback model is available")
func chatViewModelRecoveryWithoutFallbackModel() async throws {
    let primary = InferenceModelDescriptor(
        identifier: "primary-model",
        displayName: "Primary",
        contextWindow: 32_768
    )
    let client = FailoverInferenceClient(unavailableModelIDs: [primary.identifier])
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore(),
        fallbackModels: [],
        model: primary
    )

    viewModel.draft = "hello"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming && viewModel.errorMessage != nil
    }

    #expect(viewModel.model.identifier == primary.identifier)
    #expect(viewModel.recoveryHint?.action == .retryLastPrompt)
}

private actor FailoverInferenceClient: InferenceClient {
    private let unavailableModelIDs: Set<String>
    private(set) var loadModelIDs: [String] = []

    init(unavailableModelIDs: Set<String>) {
        self.unavailableModelIDs = unavailableModelIDs
    }

    func loadModel(_ model: InferenceModelDescriptor) async throws {
        loadModelIDs.append(model.identifier)
        if unavailableModelIDs.contains(model.identifier) {
            throw LocalRuntimeInferenceError.unavailable("Runtime unavailable for \(model.identifier)")
        }
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
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
