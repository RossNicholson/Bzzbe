#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel slash preset command updates controls without calling inference")
func slashPresetCommandUpdatesControls() async throws {
    let client = CommandCaptureInferenceClient()
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore()
    )

    viewModel.draft = "/preset creative"
    viewModel.sendDraft()

    #expect(viewModel.selectedPreset == .creative)
    #expect(viewModel.temperature == 1.1)
    #expect(viewModel.topP == 0.97)
    #expect(viewModel.topK == 80)
    #expect(viewModel.maxOutputTokens == 1024)
    #expect(viewModel.messages.isEmpty)

    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

@MainActor
@Test("ChatViewModel slash tuning command sets custom preset and feedback")
func slashTemperatureCommandSetsCustomPreset() {
    let viewModel = ChatViewModel(
        inferenceClient: MockInferenceClient(),
        conversationStore: InMemoryConversationStore()
    )

    viewModel.draft = "/temperature 1.25"
    viewModel.sendDraft()

    #expect(viewModel.selectedPreset == .custom)
    #expect(viewModel.temperature == 1.25)
    #expect(viewModel.commandFeedback?.contains("Temperature set") == true)
    #expect(viewModel.messages.isEmpty)
}

@MainActor
@Test("ChatViewModel slash help command shows available commands")
func slashHelpCommandShowsUsage() {
    let viewModel = ChatViewModel(
        inferenceClient: MockInferenceClient(),
        conversationStore: InMemoryConversationStore()
    )

    viewModel.draft = "/help"
    viewModel.sendDraft()

    #expect(viewModel.commandFeedback?.contains("/preset") == true)
    #expect(viewModel.messages.isEmpty)
}

private actor CommandCaptureInferenceClient: InferenceClient {
    private(set) var loadModelCallCount: Int = 0
    private(set) var streamCallCount: Int = 0

    func loadModel(_ model: InferenceModelDescriptor) async throws {
        loadModelCallCount += 1
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(modelIdentifier: request.model.identifier))
            continuation.yield(.token("ok"))
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    func cancelCurrentRequest() async {}
}
#endif
