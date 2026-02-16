#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreInference
import CoreStorage
import Foundation
import Testing

@MainActor
@Test("ChatViewModel restores latest conversation and supports history selection")
func chatViewModelRestoresAndSelectsHistory() async throws {
    let store = InMemoryConversationStore()

    let earlierConversation = try await store.createConversation(title: "Earlier")
    _ = try await store.addMessage(conversationID: earlierConversation.id, role: .user, content: "earlier user")
    _ = try await store.addMessage(conversationID: earlierConversation.id, role: .assistant, content: "earlier assistant")

    let latestConversation = try await store.createConversation(title: "Latest")
    _ = try await store.addMessage(conversationID: latestConversation.id, role: .user, content: "latest user")
    _ = try await store.addMessage(conversationID: latestConversation.id, role: .assistant, content: "latest assistant")

    let viewModel = ChatViewModel(
        inferenceClient: MockInferenceClient(),
        conversationStore: store
    )

    try await eventually {
        viewModel.conversations.count == 2 &&
            viewModel.activeConversationID == latestConversation.id
    }

    #expect(viewModel.messages.map(\.content) == ["latest user", "latest assistant"])

    viewModel.selectConversation(id: earlierConversation.id)
    try await eventually {
        viewModel.activeConversationID == earlierConversation.id
    }

    #expect(viewModel.messages.map(\.content) == ["earlier user", "earlier assistant"])
}

@MainActor
@Test("ChatViewModel delete removes conversation from store and active history list")
func chatViewModelDeleteConversation() async throws {
    let store = InMemoryConversationStore()

    let firstConversation = try await store.createConversation(title: "First")
    _ = try await store.addMessage(conversationID: firstConversation.id, role: .user, content: "first message")

    let secondConversation = try await store.createConversation(title: "Second")
    _ = try await store.addMessage(conversationID: secondConversation.id, role: .user, content: "second message")

    let viewModel = ChatViewModel(
        inferenceClient: MockInferenceClient(),
        conversationStore: store
    )

    try await eventually {
        viewModel.conversations.count == 2 &&
            viewModel.activeConversationID == secondConversation.id
    }

    viewModel.deleteConversation(id: secondConversation.id)
    try await eventually {
        viewModel.conversations.count == 1 &&
            viewModel.activeConversationID == firstConversation.id
    }

    #expect(viewModel.conversations.map(\.id) == [firstConversation.id])
    #expect(viewModel.messages.map(\.content) == ["first message"])
    #expect(try await store.fetchConversation(id: secondConversation.id) == nil)

    viewModel.deleteConversation(id: firstConversation.id)
    try await eventually {
        viewModel.conversations.isEmpty &&
            viewModel.activeConversationID == nil &&
            viewModel.messages.isEmpty
    }

    #expect(try await store.fetchConversation(id: firstConversation.id) == nil)
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
