#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreAgents
import CoreInference
import Foundation
import Testing

@MainActor
@Test("TaskWorkspaceViewModel runs selected task and captures history")
func taskWorkspaceRunsTaskAndCapturesHistory() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("First "),
            .token("Second"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        model: model
    )

    viewModel.userInput = "Summarize this text."
    viewModel.runSelectedTask()

    try await eventually {
        !viewModel.isRunning && viewModel.output == "First Second"
    }

    #expect(viewModel.runHistory.count == 1)
    #expect(viewModel.runHistory.first?.status == .completed)
    #expect(viewModel.runHistory.first?.taskID == viewModel.selectedTaskID)
}

@MainActor
@Test("TaskWorkspaceViewModel records failure when runtime fails")
func taskWorkspaceRecordsFailure() async throws {
    let client = StubTaskInferenceClient(
        events: [],
        streamError: LocalRuntimeInferenceError.unavailable("Connection refused")
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        model: model
    )

    viewModel.userInput = "Explain this code"
    viewModel.runSelectedTask()

    try await eventually {
        !viewModel.isRunning && viewModel.runHistory.first?.status == .failed
    }

    #expect(viewModel.errorMessage?.contains("Connection refused") == true)
}

@MainActor
@Test("TaskWorkspaceViewModel blocks task runs when tool profile is insufficient")
func taskWorkspaceBlocksInsufficientToolProfile() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Should not run"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .readOnly),
        model: model
    )

    viewModel.selectedTaskID = "organize_files_plan"
    viewModel.userInput = "Plan a folder structure for my downloads."
    viewModel.runSelectedTask()

    #expect(viewModel.isRunning == false)
    #expect(viewModel.runHistory.isEmpty)
    #expect(viewModel.errorMessage?.contains("requires Local files") == true)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

@MainActor
@Test("TaskWorkspaceViewModel enforces layered policy minimums")
func taskWorkspaceBlocksWhenPolicyMinimumExceedsTaskRequirement() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Should not run"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let pipeline = ToolPermissionPolicyPipeline(
        minimumProfileByTaskID: ["summarize": .advanced]
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .localFiles),
        toolPermissionPolicyPipeline: pipeline,
        model: model
    )

    viewModel.selectedTaskID = "summarize"
    viewModel.userInput = "Summarize this release note."
    viewModel.runSelectedTask()

    #expect(viewModel.isRunning == false)
    #expect(viewModel.runHistory.isEmpty)
    #expect(viewModel.errorMessage?.contains("Policy minimum") == true)
    #expect(viewModel.selectedTaskEffectiveRequiredProfile == .advanced)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

@MainActor
@Test("TaskWorkspaceViewModel requires approval for risky tasks and supports allow once")
func taskWorkspaceRequiresApprovalForRiskyTasks() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Approved"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let approvals = StubTaskApprovalRuleProvider()
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .localFiles),
        taskApprovalRuleProvider: approvals,
        model: model
    )

    viewModel.selectedTaskID = "organize_files_plan"
    viewModel.userInput = "Create a plan for my Downloads folder."
    viewModel.runSelectedTask()

    #expect(viewModel.pendingApproval?.taskID == "organize_files_plan")
    #expect(viewModel.isRunning == false)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)

    viewModel.resolvePendingApproval(.allowOnce)

    try await eventually {
        !viewModel.isRunning && viewModel.runHistory.first?.status == .completed
    }
    #expect(viewModel.pendingApproval == nil)
    #expect(approvals.alwaysAllowedTaskIDs.isEmpty)
    #expect(await client.loadModelCallCount == 1)
    #expect(await client.streamCallCount == 1)
}

@MainActor
@Test("TaskWorkspaceViewModel persists always-allow approval decisions")
func taskWorkspacePersistsAlwaysAllowApprovals() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Approved"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let approvals = StubTaskApprovalRuleProvider()
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .localFiles),
        taskApprovalRuleProvider: approvals,
        model: model
    )

    viewModel.selectedTaskID = "organize_files_plan"
    viewModel.userInput = "Create a plan for my Downloads folder."
    viewModel.runSelectedTask()
    #expect(viewModel.pendingApproval != nil)

    viewModel.resolvePendingApproval(.alwaysAllow)
    try await eventually {
        !viewModel.isRunning && viewModel.runHistory.count == 1
    }

    #expect(approvals.alwaysAllowedTaskIDs.contains("organize_files_plan"))
    #expect(await client.streamCallCount == 1)

    viewModel.userInput = "Create another plan."
    viewModel.runSelectedTask()

    try await eventually {
        !viewModel.isRunning && viewModel.runHistory.count == 2
    }

    #expect(viewModel.pendingApproval == nil)
    #expect(await client.streamCallCount == 2)
}

@MainActor
@Test("TaskWorkspaceViewModel approval requests time out")
func taskWorkspaceApprovalTimesOut() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Should not run"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let approvals = StubTaskApprovalRuleProvider()
    var now = Date(timeIntervalSince1970: 1_000)
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .localFiles),
        taskApprovalRuleProvider: approvals,
        nowProvider: { now },
        approvalTimeout: 1,
        model: model
    )

    viewModel.selectedTaskID = "organize_files_plan"
    viewModel.userInput = "Create a plan for my Downloads folder."
    viewModel.runSelectedTask()

    #expect(viewModel.pendingApproval != nil)
    now = now.addingTimeInterval(2)
    viewModel.resolvePendingApproval(.allowOnce)

    #expect(viewModel.pendingApproval == nil)
    #expect(viewModel.errorMessage?.contains("timed out") == true)
    #expect(viewModel.runHistory.isEmpty)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

private struct StubToolPermissionProfileProvider: ToolPermissionProfileProviding {
    let profile: AgentToolAccessLevel

    func currentProfile() -> AgentToolAccessLevel {
        profile
    }
}

private final class StubTaskApprovalRuleProvider: TaskApprovalRuleProviding {
    private(set) var alwaysAllowedTaskIDs: Set<String>

    init(alwaysAllowedTaskIDs: Set<String> = []) {
        self.alwaysAllowedTaskIDs = alwaysAllowedTaskIDs
    }

    func isAlwaysAllowed(taskID: String) -> Bool {
        alwaysAllowedTaskIDs.contains(taskID)
    }

    func allowAlways(taskID: String) {
        alwaysAllowedTaskIDs.insert(taskID)
    }
}

private actor StubTaskInferenceClient: InferenceClient {
    private let events: [InferenceEvent]
    private let loadError: Error?
    private let streamError: Error?
    private(set) var loadModelCallCount: Int = 0
    private(set) var streamCallCount: Int = 0

    init(
        events: [InferenceEvent],
        loadError: Error? = nil,
        streamError: Error? = nil
    ) {
        self.events = events
        self.loadError = loadError
        self.streamError = streamError
    }

    func loadModel(_ model: InferenceModelDescriptor) async throws {
        loadModelCallCount += 1
        if let loadError {
            throw loadError
        }
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let streamError {
                continuation.finish(throwing: streamError)
            } else {
                continuation.finish()
            }
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

    throw TaskWorkspacePollingTimeoutError()
}

private struct TaskWorkspacePollingTimeoutError: Error {}
#endif
