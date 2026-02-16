#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel surfaces retry recovery hint when runtime is unavailable")
func chatRecoveryHintForRuntimeUnavailable() async throws {
    let viewModel = ChatViewModel(
        inferenceClient: FailingInferenceClient(error: LocalRuntimeInferenceError.unavailable("Connection refused")),
        conversationStore: InMemoryConversationStore()
    )

    viewModel.draft = "Hello"
    viewModel.sendDraft()

    try await eventually {
        viewModel.errorMessage != nil && !viewModel.isStreaming
    }

    #expect(viewModel.recoveryHint?.action == .retryLastPrompt)
    #expect(viewModel.recoveryHint?.actionTitle == "Retry Request")
}

@MainActor
@Test("ChatViewModel offers one-click setup rerun for missing model failures")
func chatRecoveryHintForMissingModel() async throws {
    var didRequestSetupRerun = false
    let viewModel = ChatViewModel(
        inferenceClient: FailingInferenceClient(error: LocalRuntimeInferenceError.runtime("model not found")),
        conversationStore: InMemoryConversationStore(),
        onRequestSetupRerun: { didRequestSetupRerun = true }
    )

    viewModel.draft = "Hello"
    viewModel.sendDraft()

    try await eventually {
        viewModel.recoveryHint?.action == .rerunSetup
    }

    viewModel.performRecoveryAction()
    #expect(didRequestSetupRerun == true)
}

private actor FailingInferenceClient: InferenceClient {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func loadModel(_ model: InferenceModelDescriptor) async throws {
        throw error
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
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
