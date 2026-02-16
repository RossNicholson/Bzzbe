public struct AgentTask: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct AgentTaskTemplate: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let inputHint: String
    public let systemPrompt: String

    public init(
        id: String,
        name: String,
        summary: String,
        inputHint: String,
        systemPrompt: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.inputHint = inputHint
        self.systemPrompt = systemPrompt
    }
}

public struct AgentCatalog {
    public init() {}

    public func starterTasks() -> [AgentTask] {
        templates().map { AgentTask(id: $0.id, name: $0.name) }
    }

    public func templates() -> [AgentTaskTemplate] {
        [
            AgentTaskTemplate(
                id: "summarize",
                name: "Summarize Text",
                summary: "Turn long text into clear bullet points and next actions.",
                inputHint: "Paste notes, transcript, or article text to summarize.",
                systemPrompt: """
                You summarize text into concise bullets. Return:
                1) A short overview.
                2) Key points.
                3) Clear next actions.
                """
            ),
            AgentTaskTemplate(
                id: "rewrite_tone",
                name: "Rewrite for Tone",
                summary: "Rewrite text for the selected tone while preserving meaning.",
                inputHint: "Paste text and specify desired tone, e.g. formal or friendly.",
                systemPrompt: """
                Rewrite the user's text in the requested tone while preserving intent.
                Keep it concise and do not invent facts.
                """
            ),
            AgentTaskTemplate(
                id: "code_explain",
                name: "Explain Code",
                summary: "Explain code behavior and call out risks and improvements.",
                inputHint: "Paste a code snippet and language context.",
                systemPrompt: """
                Explain code in practical engineering terms:
                - What it does
                - Risks or bugs
                - Improvements
                Prefer direct, actionable feedback.
                """
            ),
            AgentTaskTemplate(
                id: "test_generation",
                name: "Generate Unit Tests",
                summary: "Draft focused unit tests for pasted source code.",
                inputHint: "Paste source code and include testing framework if known.",
                systemPrompt: """
                Generate targeted unit tests for the provided code.
                Cover success, edge, and failure paths.
                Keep tests deterministic.
                """
            ),
            AgentTaskTemplate(
                id: "organize_files_plan",
                name: "Folder Organization Plan",
                summary: "Create a dry-run file organization plan without deleting files.",
                inputHint: "Describe folder goals and provide a file list if available.",
                systemPrompt: """
                Build a safe file organization plan.
                Always provide a dry-run preview first.
                Never suggest destructive actions without explicit confirmation.
                """
            )
        ]
    }

    public func template(id: String) -> AgentTaskTemplate? {
        templates().first(where: { $0.id == id })
    }
}
