import CoreStorage
import Foundation
import Testing

@Test("InMemoryConversationStore supports CRUD conversations and messages")
func inMemoryStoreCRUD() async throws {
    let store = InMemoryConversationStore()
    let created = try await store.createConversation(title: "Test Conversation")
    #expect(created.title == "Test Conversation")

    let userMessage = try await store.addMessage(
        conversationID: created.id,
        role: .user,
        content: "hello"
    )
    let assistantMessage = try await store.addMessage(
        conversationID: created.id,
        role: .assistant,
        content: "world"
    )

    let fetched = try await store.fetchConversation(id: created.id)
    #expect(fetched?.id == created.id)

    try await store.renameConversation(id: created.id, title: "Renamed")
    let renamed = try await store.fetchConversation(id: created.id)
    #expect(renamed?.title == "Renamed")

    let messages = try await store.listMessages(conversationID: created.id)
    #expect(messages.map(\.id) == [userMessage.id, assistantMessage.id])
    #expect(messages.map(\.content) == [userMessage.content, assistantMessage.content])
    #expect(messages.map(\.role) == [userMessage.role, assistantMessage.role])

    try await store.deleteConversation(id: created.id)
    let deleted = try await store.fetchConversation(id: created.id)
    #expect(deleted == nil)
    let deletedMessages = try await store.listMessages(conversationID: created.id)
    #expect(deletedMessages.isEmpty)
}

@Test("SQLiteConversationStore supports CRUD conversations and messages")
func sqliteStoreCRUD() async throws {
    let store = try SQLiteConversationStore(databaseURL: makeTemporaryDatabaseURL())
    let created = try await store.createConversation(title: "SQL Conversation")
    #expect(created.title == "SQL Conversation")

    let userMessage = try await store.addMessage(
        conversationID: created.id,
        role: .user,
        content: "ping"
    )
    let assistantMessage = try await store.addMessage(
        conversationID: created.id,
        role: .assistant,
        content: "pong"
    )

    let fetched = try await store.fetchConversation(id: created.id)
    #expect(fetched?.id == created.id)
    #expect((fetched?.updatedAt ?? .distantPast) >= created.updatedAt)

    let messages = try await store.listMessages(conversationID: created.id)
    #expect(messages.map(\.id) == [userMessage.id, assistantMessage.id])
    #expect(messages.map(\.content) == [userMessage.content, assistantMessage.content])
    #expect(messages.map(\.role) == [userMessage.role, assistantMessage.role])

    try await store.renameConversation(id: created.id, title: "SQL Renamed")
    let renamed = try await store.fetchConversation(id: created.id)
    #expect(renamed?.title == "SQL Renamed")

    try await store.deleteConversation(id: created.id)
    let deletedConversation = try await store.fetchConversation(id: created.id)
    #expect(deletedConversation == nil)

    let deletedMessages = try await store.listMessages(conversationID: created.id)
    #expect(deletedMessages.isEmpty)
}

@Test("SQLiteConversationStore orders conversations by updated_at descending")
func sqliteStoreListOrdering() async throws {
    let store = try SQLiteConversationStore(databaseURL: makeTemporaryDatabaseURL())

    let older = try await store.createConversation(title: "Older")
    let newer = try await store.createConversation(title: "Newer")

    _ = try await store.addMessage(conversationID: older.id, role: .user, content: "touch")
    let conversations = try await store.listConversations()

    #expect(conversations.count == 2)
    #expect(conversations.first?.id == older.id)
    #expect(conversations.last?.id == newer.id)
}

private func makeTemporaryDatabaseURL() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-tests", isDirectory: true)
    let filename = "conversations-\(UUID().uuidString).sqlite3"
    return root.appendingPathComponent(filename, isDirectory: false)
}
