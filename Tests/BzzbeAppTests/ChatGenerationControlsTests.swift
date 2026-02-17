#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel sends selected generation controls in inference request")
func chatViewModelSendsGenerationControls() async throws {
    let client = CapturingInferenceClient()
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore()
    )

    viewModel.applyPreset(.creative)
    viewModel.draft = "Write a short poem"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    let request = try #require(await client.lastRequest)
    #expect(request.temperature == 1.1)
    #expect(request.topP == 0.97)
    #expect(request.topK == 80)
    #expect(request.maxOutputTokens == 1024)
}

@MainActor
@Test("ChatViewModel marks preset as custom when controls are edited")
func chatViewModelUsesCustomPresetForManualControls() {
    let viewModel = ChatViewModel(
        inferenceClient: MockInferenceClient(),
        conversationStore: InMemoryConversationStore()
    )

    viewModel.applyPreset(.balanced)
    #expect(viewModel.selectedPreset == .balanced)

    viewModel.setTemperature(1.25)
    #expect(viewModel.selectedPreset == .custom)

    viewModel.applyPreset(.accurate)
    #expect(viewModel.selectedPreset == .accurate)
    #expect(viewModel.temperature == 0.2)
    #expect(viewModel.topP == 0.7)
    #expect(viewModel.topK == 20)
    #expect(viewModel.maxOutputTokens == 512)
}

private actor CapturingInferenceClient: InferenceClient {
    private(set) var lastRequest: InferenceRequest?

    func loadModel(_ model: InferenceModelDescriptor) async throws {}

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        lastRequest = request
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(modelIdentifier: request.model.identifier))
            continuation.yield(.token("Done"))
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
