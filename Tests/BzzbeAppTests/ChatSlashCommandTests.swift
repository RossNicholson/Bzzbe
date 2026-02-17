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
    #expect(viewModel.commandFeedback?.contains("/compact") == true)
    #expect(viewModel.messages.isEmpty)
}

@MainActor
@Test("ChatViewModel slash compact command summarizes older context without inference call")
func slashCompactCommandCompactsConversationContext() async throws {
    let store = InMemoryConversationStore()
    let conversation = try await store.createConversation(title: "Long Chat")
    for index in 0..<16 {
        let role: ConversationMessageRole = index.isMultiple(of: 2) ? .user : .assistant
        _ = try await store.addMessage(
            conversationID: conversation.id,
            role: role,
            content: "Message \(index + 1): \(String(repeating: "detail ", count: 20))"
        )
    }

    let client = CommandCaptureInferenceClient()
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: store
    )

    try await eventually {
        viewModel.activeConversationID == conversation.id && viewModel.messages.count == 16
    }

    let preCompactCount = viewModel.messages.count

    viewModel.draft = "/compact Focus on decisions"
    viewModel.sendDraft()

    #expect(viewModel.messages.count < preCompactCount)
    #expect(viewModel.messages.first?.content.contains("Compacted conversation summary") == true)
    #expect(viewModel.commandFeedback?.contains("Compacted older context") == true)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

@MainActor
@Test("ChatViewModel treats unknown slash input as normal prompt")
func slashUnknownFallsBackToPrompt() async throws {
    let client = CommandCaptureInferenceClient()
    let viewModel = ChatViewModel(
        inferenceClient: client,
        conversationStore: InMemoryConversationStore()
    )

    viewModel.draft = "/usr/bin/env"
    viewModel.sendDraft()

    try await eventually {
        !viewModel.isStreaming
    }

    #expect(viewModel.messages.first?.content == "/usr/bin/env")
    #expect(await client.loadModelCallCount == 1)
    #expect(await client.streamCallCount == 1)
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
