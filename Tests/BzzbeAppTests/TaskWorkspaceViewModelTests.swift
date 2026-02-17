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
    #expect(viewModel.statusText.contains("Settings > Tools") == true)
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

@MainActor
@Test("TaskWorkspaceViewModel blocks risky tasks that violate sandbox policy")
func taskWorkspaceBlocksSandboxViolations() async throws {
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
    let approvals = StubTaskApprovalRuleProvider(alwaysAllowedTaskIDs: ["organize_files_plan"])
    let sandboxPolicy = ToolExecutionSandboxPolicy(
        configuration: ToolExecutionSandboxConfiguration(
            allowedPathPrefixes: ["/Users/test-safe-root"],
            allowedNetworkHosts: [],
            allowHostNetwork: false,
            allowPrivilegeEscalation: false,
            blockedMountPrefixes: ["/"]
        )
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        toolPermissionProvider: StubToolPermissionProfileProvider(profile: .localFiles),
        taskApprovalRuleProvider: approvals,
        toolExecutionSandboxPolicy: sandboxPolicy,
        model: model
    )

    viewModel.selectedTaskID = "organize_files_plan"
    viewModel.userInput = "Organize files in /etc and /var/tmp."
    viewModel.runSelectedTask()

    #expect(viewModel.isRunning == false)
    #expect(viewModel.runHistory.isEmpty)
    #expect(viewModel.errorMessage?.contains("Sandbox blocked request") == true)
    #expect(viewModel.statusText.contains("sandbox policy") == true)
    #expect(await client.loadModelCallCount == 0)
    #expect(await client.streamCallCount == 0)
}

@MainActor
@Test("TaskWorkspaceViewModel runs due scheduled jobs and records scheduler logs")
func taskWorkspaceRunsDueScheduledJobs() async throws {
    let client = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Scheduled result"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let schedulerStore = InMemoryScheduledTaskStateStore()
    let scheduler = JSONScheduledTaskScheduler(stateStore: schedulerStore)
    var now = Date(timeIntervalSince1970: 4_000)
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        scheduledTaskScheduler: scheduler,
        nowProvider: { now },
        model: model
    )

    viewModel.selectedTaskID = "summarize"
    viewModel.userInput = "Summarize this weekly update."
    viewModel.scheduleMode = .oneShot
    viewModel.scheduledRunAt = now
    viewModel.scheduleSelectedTask()
    #expect(viewModel.scheduledJobs.count == 1)

    viewModel.runDueScheduledJobs()
    try await eventually {
        !viewModel.isRunning && viewModel.runHistory.first?.status == .completed
    }

    now = now.addingTimeInterval(10)
    viewModel.refreshScheduledState()
    #expect(viewModel.scheduledJobs.isEmpty)
    #expect(viewModel.scheduledRunLogs.first?.status == .completed)
    #expect(await client.streamCallCount == 1)
}

@MainActor
@Test("TaskWorkspaceViewModel refreshes scheduler summary with due-now context")
func taskWorkspaceRefreshesSchedulerSummary() async throws {
    let client = StubTaskInferenceClient(events: [])
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let schedulerStore = InMemoryScheduledTaskStateStore()
    let scheduler = JSONScheduledTaskScheduler(stateStore: schedulerStore)
    var now = Date(timeIntervalSince1970: 8_000)
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: client,
        scheduledTaskScheduler: scheduler,
        nowProvider: { now },
        model: model
    )

    viewModel.selectedTaskID = "summarize"
    viewModel.userInput = "Summarize this weekly update."
    viewModel.scheduleMode = .oneShot
    viewModel.scheduledRunAt = now.addingTimeInterval(3_600)
    viewModel.scheduleSelectedTask()

    #expect(viewModel.schedulerSummaryText.contains("1 scheduled job"))
    #expect(viewModel.dueScheduledJobCount == 0)

    now = now.addingTimeInterval(3_601)
    viewModel.refreshScheduledState()
    #expect(viewModel.schedulerSummaryText.contains("1 job due now"))
    #expect(viewModel.dueScheduledJobCount == 1)
}

@MainActor
@Test("TaskWorkspaceViewModel tracks sub-agent lifecycle and output handoff")
func taskWorkspaceTracksSubAgentLifecycle() async throws {
    let mainClient = StubTaskInferenceClient(events: [])
    let subAgentClient = StubTaskInferenceClient(
        events: [
            .started(modelIdentifier: "qwen3:8b"),
            .token("Child "),
            .token("output"),
            .completed
        ]
    )
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: mainClient,
        subAgentInferenceClientFactory: { subAgentClient },
        model: model
    )

    viewModel.selectedTaskID = "summarize"
    viewModel.userInput = "Summarize this weekly update."
    viewModel.startSubAgentForSelectedTask()

    try await eventually {
        viewModel.subAgentRuns.first?.status == .completed
    }

    guard let run = viewModel.subAgentRuns.first else {
        Issue.record("Expected sub-agent run")
        return
    }

    #expect(run.output == "Child output")
    viewModel.useSubAgentOutput(run.id)
    #expect(viewModel.userInput == "Child output")
    #expect(await subAgentClient.streamCallCount == 1)
    #expect(await mainClient.streamCallCount == 0)
}

@MainActor
@Test("TaskWorkspaceViewModel can cancel in-flight sub-agent runs")
func taskWorkspaceCancelsSubAgentRun() async throws {
    let model = InferenceModelDescriptor(
        identifier: "qwen3:8b",
        displayName: "Qwen 3 8B",
        contextWindow: 32_768
    )
    let hangingSubAgentClient = HangingSubAgentInferenceClient()
    let viewModel = TaskWorkspaceViewModel(
        inferenceClient: StubTaskInferenceClient(events: []),
        subAgentInferenceClientFactory: { hangingSubAgentClient },
        model: model
    )

    viewModel.selectedTaskID = "summarize"
    viewModel.userInput = "Summarize this weekly update."
    viewModel.startSubAgentForSelectedTask()

    try await eventually {
        viewModel.subAgentRuns.first?.status == .running
    }
    guard let runID = viewModel.subAgentRuns.first?.id else {
        Issue.record("Expected running sub-agent")
        return
    }

    viewModel.cancelSubAgentRun(runID)

    try await eventually {
        viewModel.subAgentRuns.first?.status == .cancelled
    }
    #expect(await hangingSubAgentClient.streamCallCount == 1)
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

private final class InMemoryScheduledTaskStateStore: ScheduledTaskStateStoring {
    private var state: ScheduledTaskState = .empty

    func loadState() throws -> ScheduledTaskState {
        state
    }

    func saveState(_ state: ScheduledTaskState) throws {
        self.state = state
    }
}

private actor HangingSubAgentInferenceClient: InferenceClient {
    private(set) var streamCallCount: Int = 0

    func loadModel(_: InferenceModelDescriptor) async throws {}

    func streamCompletion(_: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        streamCallCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(modelIdentifier: "qwen3:8b"))
        }
    }

    func cancelCurrentRequest() async {}
}
#endif
