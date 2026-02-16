public struct AgentTask: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AgentCatalog {
    public init() {}

    public func starterTasks() -> [AgentTask] {
        [
            AgentTask(id: "summarize", name: "Summarize Text"),
            AgentTask(id: "rewrite", name: "Rewrite for Tone")
        ]
    }
}
