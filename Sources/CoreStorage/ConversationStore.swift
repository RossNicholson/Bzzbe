public struct Conversation: Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public protocol ConversationStoring {
    func listConversations() async throws -> [Conversation]
}

public struct InMemoryConversationStore: ConversationStoring {
    public init() {}

    public func listConversations() async throws -> [Conversation] {
        []
    }
}
