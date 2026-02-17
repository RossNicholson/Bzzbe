public struct AgentTask: Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AgentToolAccessLevel: String, Sendable, Equatable, CaseIterable {
    case readOnly = "read_only"
    case localFiles = "local_files"
    case advanced = "advanced"

    public var title: String {
        switch self {
        case .readOnly:
            return "Read-only"
        case .localFiles:
            return "Local files"
        case .advanced:
            return "Advanced"
        }
    }

    public var summary: String {
        switch self {
        case .readOnly:
            return "No external tools, content transformation only."
        case .localFiles:
            return "Allows local file planning and file-context workflows."
        case .advanced:
            return "Allows higher-trust tool use and automation workflows."
        }
    }

    public var rank: Int {
        switch self {
        case .readOnly:
            return 0
        case .localFiles:
            return 1
        case .advanced:
            return 2
        }
    }

    public func satisfies(_ required: AgentToolAccessLevel) -> Bool {
        rank >= required.rank
    }
}

public struct AgentTaskTemplate: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let inputHint: String
    public let systemPrompt: String
    public let requiredToolAccess: AgentToolAccessLevel

    public init(
        id: String,
        name: String,
        summary: String,
        inputHint: String,
        systemPrompt: String,
        requiredToolAccess: AgentToolAccessLevel = .readOnly
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.inputHint = inputHint
        self.systemPrompt = systemPrompt
        self.requiredToolAccess = requiredToolAccess
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
                """,
                requiredToolAccess: .readOnly
            ),
            AgentTaskTemplate(
                id: "rewrite_tone",
                name: "Rewrite for Tone",
                summary: "Rewrite text for the selected tone while preserving meaning.",
                inputHint: "Paste text and specify desired tone, e.g. formal or friendly.",
                systemPrompt: """
                Rewrite the user's text in the requested tone while preserving intent.
                Keep it concise and do not invent facts.
                """,
                requiredToolAccess: .readOnly
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
                """,
                requiredToolAccess: .readOnly
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
                """,
                requiredToolAccess: .readOnly
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
                """,
                requiredToolAccess: .localFiles
            )
        ]
    }

    public func template(id: String) -> AgentTaskTemplate? {
        templates().first(where: { $0.id == id })
    }
}
