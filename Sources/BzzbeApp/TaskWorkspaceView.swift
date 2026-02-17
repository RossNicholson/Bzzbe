#if canImport(SwiftUI)
import CoreAgents
import CoreInference
import Foundation
import SwiftUI

@MainActor
final class TaskWorkspaceViewModel: ObservableObject {
    enum RunStatus: String, Equatable {
        case completed
        case failed
        case cancelled
    }

    enum ScheduleMode: String, CaseIterable {
        case oneShot
        case recurring

        var title: String {
            switch self {
            case .oneShot:
                return "One-shot"
            case .recurring:
                return "Recurring"
            }
        }
    }

    enum ApprovalDecision {
        case allowOnce
        case alwaysAllow
        case deny
    }

    struct TaskRun: Identifiable, Equatable {
        let id: UUID
        let startedAt: Date
        let taskID: String
        let taskName: String
        let inputPreview: String
        let outputPreview: String
        let status: RunStatus
    }

    struct TaskApprovalPrompt: Equatable {
        let id: UUID
        let taskID: String
        let taskName: String
        let reason: String
        let expiresAt: Date
    }

    enum SubAgentRunStatus: String, Equatable {
        case queued
        case running
        case completed
        case failed
        case cancelled
    }

    struct SubAgentRun: Identifiable, Equatable {
        let id: UUID
        let taskID: String
        let taskName: String
        let inputPreview: String
        let createdAt: Date
        var status: SubAgentRunStatus
        var output: String
        var errorMessage: String?
    }

    private struct PendingApprovalContext {
        let task: AgentTaskTemplate
        let input: String
    }

    @Published private(set) var tasks: [AgentTaskTemplate]
    @Published var selectedTaskID: String
    @Published var userInput: String = ""
    @Published private(set) var output: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusText: String = "Choose a task and run it."
    @Published private(set) var errorMessage: String?
    @Published private(set) var runHistory: [TaskRun] = []
    @Published private(set) var toolPermissionProfile: AgentToolAccessLevel
    @Published private(set) var pendingApproval: TaskApprovalPrompt?
    @Published private(set) var sandboxStatusText: String = "Sandbox checks idle."
    @Published private(set) var sandboxGuidance: [String] = []
    @Published private(set) var sandboxDiagnostics: [String] = []
    @Published var scheduleMode: ScheduleMode = .oneShot
    @Published var scheduledRunAt: Date = Date().addingTimeInterval(300)
    @Published var recurringIntervalMinutes: Int = 60
    @Published private(set) var scheduledJobs: [ScheduledTaskJob] = []
    @Published private(set) var scheduledRunLogs: [ScheduledTaskRunLog] = []
    @Published private(set) var schedulerStatusText: String = "No scheduled jobs yet."
    @Published private(set) var schedulerSummaryText: String = "No scheduled jobs."
    @Published private(set) var subAgentRuns: [SubAgentRun] = []

    let model: InferenceModelDescriptor

    private let inferenceClient: any InferenceClient
    private let toolPermissionProvider: any ToolPermissionProfileProviding
    private let toolPermissionPolicyPipeline: ToolPermissionPolicyPipeline
    private let taskApprovalRuleProvider: any TaskApprovalRuleProviding
    private let toolExecutionSandboxPolicy: ToolExecutionSandboxPolicy
    private let scheduledTaskScheduler: ScheduledTaskScheduling
    private let subAgentInferenceClientFactory: () -> any InferenceClient
    private let nowProvider: () -> Date
    private let approvalTimeout: TimeInterval
    private var streamTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeTaskTemplate: AgentTaskTemplate?
    private var activeTaskInput: String = ""
    private var activeTaskStartedAt: Date = Date()
    private var activeScheduledJobID: UUID?
    private var pendingApprovalContext: PendingApprovalContext?
    private var subAgentTasks: [UUID: Task<Void, Never>] = [:]

    init(
        catalog: AgentCatalog = AgentCatalog(),
        inferenceClient: any InferenceClient = LocalRuntimeInferenceClient(),
        toolPermissionProvider: any ToolPermissionProfileProviding = DefaultsToolPermissionProfileProvider(),
        toolPermissionPolicyPipeline: ToolPermissionPolicyPipeline = ToolPermissionPolicyPipeline(),
        taskApprovalRuleProvider: any TaskApprovalRuleProviding = DefaultsTaskApprovalRuleProvider(),
        toolExecutionSandboxPolicy: ToolExecutionSandboxPolicy = ToolExecutionSandboxPolicy(),
        scheduledTaskScheduler: ScheduledTaskScheduling = JSONScheduledTaskScheduler(),
        subAgentInferenceClientFactory: @escaping () -> any InferenceClient = { LocalRuntimeInferenceClient() },
        nowProvider: @escaping () -> Date = Date.init,
        approvalTimeout: TimeInterval = 90,
        model: InferenceModelDescriptor
    ) {
        let templates = catalog.templates()
        self.tasks = templates
        self.selectedTaskID = templates.first?.id ?? ""
        self.inferenceClient = inferenceClient
        self.toolPermissionProvider = toolPermissionProvider
        self.toolPermissionPolicyPipeline = toolPermissionPolicyPipeline
        self.taskApprovalRuleProvider = taskApprovalRuleProvider
        self.toolExecutionSandboxPolicy = toolExecutionSandboxPolicy
        self.scheduledTaskScheduler = scheduledTaskScheduler
        self.subAgentInferenceClientFactory = subAgentInferenceClientFactory
        self.nowProvider = nowProvider
        self.approvalTimeout = approvalTimeout
        self.toolPermissionProfile = toolPermissionProvider.currentProfile()
        self.model = model
        refreshScheduledState()
    }

    var selectedTask: AgentTaskTemplate? {
        tasks.first(where: { $0.id == selectedTaskID })
    }

    var hasPermissionForSelectedTask: Bool {
        guard let selectedTask else { return true }
        return permissionEvaluation(for: selectedTask).isAllowed
    }

    var selectedTaskPolicyExplanation: String? {
        guard let selectedTask else { return nil }
        return permissionEvaluation(for: selectedTask).explanation
    }

    var selectedTaskBlockReason: String? {
        guard let selectedTask else { return nil }
        let evaluation = permissionEvaluation(for: selectedTask)
        guard let reason = evaluation.userFacingFailureReason else {
            return nil
        }
        if let settingsHint = evaluation.settingsHint {
            return "\(reason) \(settingsHint)"
        }
        return reason
    }

    var selectedTaskEffectiveRequiredProfile: AgentToolAccessLevel? {
        guard let selectedTask else { return nil }
        return permissionEvaluation(for: selectedTask).effectiveRequiredProfile
    }

    var canRun: Bool {
        !isRunning && !trimmedInput.isEmpty && selectedTask != nil && hasPermissionForSelectedTask
    }

    var canCancel: Bool {
        isRunning
    }

    var dueScheduledJobCount: Int {
        let now = nowProvider()
        return scheduledJobs.filter { $0.nextRunAt <= now }.count
    }

    func runSelectedTask() {
        guard !isRunning else { return }
        refreshToolPermissionProfile()
        sandboxStatusText = "Sandbox checks idle."
        sandboxGuidance = []
        sandboxDiagnostics = []
        guard let task = selectedTask else {
            statusText = "No task selected."
            return
        }
        let permissionEvaluation = permissionEvaluation(for: task)
        guard permissionEvaluation.isAllowed else {
            errorMessage = permissionEvaluation.userFacingFailureReason
                ?? permissionEvaluation.failureReason
                ?? "Task blocked by tool policy."
            statusText = permissionEvaluation.settingsHint ?? "Task blocked by tool policy pipeline."
            return
        }

        let input = trimmedInput
        guard !input.isEmpty else {
            statusText = "Add input to run this task."
            return
        }

        if approvalShouldExpire() {
            clearPendingApproval()
        }

        let effectiveRequiredProfile = permissionEvaluation.effectiveRequiredProfile
        let sandboxRequest = ToolExecutionSandboxRequest.fromPromptInput(input)
        let sandboxEvaluation = toolExecutionSandboxPolicy.evaluate(
            request: sandboxRequest,
            requiredProfile: effectiveRequiredProfile
        )
        sandboxStatusText = sandboxEvaluation.userSummary
        sandboxGuidance = sandboxEvaluation.remediationHints
        sandboxDiagnostics = sandboxEvaluation.configurationDiagnostics
        guard sandboxEvaluation.isAllowed else {
            if let firstHint = sandboxEvaluation.remediationHints.first {
                errorMessage = "\(sandboxEvaluation.userSummary) \(firstHint)"
            } else {
                errorMessage = sandboxEvaluation.userSummary
            }
            statusText = "Task blocked by sandbox policy."
            return
        }

        if requiresApproval(for: effectiveRequiredProfile), !taskApprovalRuleProvider.isAlwaysAllowed(taskID: task.id) {
            if
                let existingPrompt = pendingApproval,
                existingPrompt.taskID == task.id,
                pendingApprovalContext?.input == input
            {
                statusText = "Approval pending for \(task.name). Choose Allow Once, Always Allow, or Deny."
                return
            }
            presentApprovalPrompt(for: task, input: input, requiredProfile: effectiveRequiredProfile)
            return
        }

        startRun(task: task, input: input)
    }

    func resolvePendingApproval(_ decision: ApprovalDecision) {
        if approvalShouldExpire() {
            clearPendingApproval()
            errorMessage = "Approval timed out. Retry task to request approval again."
            statusText = "Approval timed out."
            return
        }
        guard let approvalContext = pendingApprovalContext else { return }

        switch decision {
        case .allowOnce:
            clearPendingApproval()
            startRun(task: approvalContext.task, input: approvalContext.input)
        case .alwaysAllow:
            taskApprovalRuleProvider.allowAlways(taskID: approvalContext.task.id)
            clearPendingApproval()
            startRun(task: approvalContext.task, input: approvalContext.input)
        case .deny:
            clearPendingApproval()
            errorMessage = "Task run denied by user approval choice."
            statusText = "Run cancelled: approval denied."
        }
    }

    private func startRun(task: AgentTaskTemplate, input: String, scheduledJobID: UUID? = nil) {
        errorMessage = nil
        output = ""
        statusText = "Starting \(task.name)..."
        isRunning = true

        let request = InferenceRequest(
            model: model,
            messages: [
                InferenceMessage(role: .system, content: task.systemPrompt),
                InferenceMessage(role: .user, content: input)
            ]
        )

        let requestID = UUID()
        activeRequestID = requestID
        activeTaskTemplate = task
        activeTaskInput = input
        activeTaskStartedAt = Date()
        activeScheduledJobID = scheduledJobID

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.inferenceClient.loadModel(self.model)
                let stream = await self.inferenceClient.streamCompletion(request)
                for try await event in stream {
                    self.handle(event: event, requestID: requestID)
                }

                if self.isActiveRequest(requestID) {
                    self.finishRun(
                        status: .completed,
                        statusText: "\(task.name) completed.",
                        requestID: requestID
                    )
                }
            } catch is CancellationError {
                self.finishRun(
                    status: .cancelled,
                    statusText: "\(task.name) cancelled.",
                    requestID: requestID
                )
            } catch {
                self.finishRun(
                    status: .failed,
                    statusText: "\(task.name) failed.",
                    errorMessage: error.localizedDescription,
                    requestID: requestID
                )
            }
        }
    }

    func cancelRun() {
        guard isRunning else { return }
        statusText = "Cancelling task..."
        streamTask?.cancel()
        Task {
            await inferenceClient.cancelCurrentRequest()
        }
    }

    func clearOutput() {
        guard !isRunning else { return }
        output = ""
        statusText = "Output cleared."
        errorMessage = nil
    }

    func scheduleSelectedTask() {
        guard let task = selectedTask else {
            schedulerStatusText = "No task selected for scheduling."
            return
        }
        let input = trimmedInput
        guard !input.isEmpty else {
            schedulerStatusText = "Add input before creating a scheduled job."
            return
        }

        do {
            switch scheduleMode {
            case .oneShot:
                try scheduledTaskScheduler.scheduleOneShot(
                    taskID: task.id,
                    taskName: task.name,
                    input: input,
                    runAt: scheduledRunAt
                )
                schedulerStatusText = "Scheduled one-shot job for \(task.name)."
            case .recurring:
                let interval = max(1, recurringIntervalMinutes)
                try scheduledTaskScheduler.scheduleRecurring(
                    taskID: task.id,
                    taskName: task.name,
                    input: input,
                    intervalMinutes: interval,
                    firstRunAt: scheduledRunAt
                )
                schedulerStatusText = "Scheduled recurring job for \(task.name) every \(interval)m."
            }
            refreshScheduledState()
        } catch {
            schedulerStatusText = "Failed to schedule task: \(error.localizedDescription)"
        }
    }

    func removeScheduledJob(_ jobID: UUID) {
        do {
            try scheduledTaskScheduler.removeJob(jobID: jobID)
            schedulerStatusText = "Removed scheduled job."
            refreshScheduledState()
        } catch {
            schedulerStatusText = "Failed to remove job: \(error.localizedDescription)"
        }
    }

    func runDueScheduledJobs() {
        guard !isRunning else { return }
        let dueJobs = scheduledTaskScheduler.dueJobs(at: nowProvider())
        guard let job = dueJobs.first else {
            schedulerStatusText = "No due jobs."
            refreshScheduledState()
            return
        }
        guard let task = tasks.first(where: { $0.id == job.taskID }) else {
            do {
                try scheduledTaskScheduler.recordRunResult(
                    jobID: job.id,
                    status: .failed,
                    message: "Task template no longer exists.",
                    at: nowProvider()
                )
                schedulerStatusText = "Skipped scheduled job: missing task template."
            } catch {
                schedulerStatusText = "Failed to update skipped scheduled job: \(error.localizedDescription)"
            }
            refreshScheduledState()
            return
        }

        statusText = "Running scheduled job: \(task.name)..."
        schedulerStatusText = "Running scheduled job now."
        startRun(task: task, input: job.input, scheduledJobID: job.id)
    }

    func startSubAgentForSelectedTask() {
        guard let task = selectedTask else {
            schedulerStatusText = "No task selected for sub-agent run."
            return
        }
        let input = trimmedInput
        guard !input.isEmpty else {
            schedulerStatusText = "Add input before launching a sub-agent."
            return
        }

        let runID = UUID()
        let run = SubAgentRun(
            id: runID,
            taskID: task.id,
            taskName: task.name,
            inputPreview: previewText(input, limit: 80),
            createdAt: nowProvider(),
            status: .queued,
            output: "",
            errorMessage: nil
        )
        subAgentRuns.insert(run, at: 0)
        if subAgentRuns.count > 20 {
            subAgentRuns = Array(subAgentRuns.prefix(20))
        }

        let client = subAgentInferenceClientFactory()
        let request = InferenceRequest(
            model: model,
            messages: [
                InferenceMessage(role: .system, content: task.systemPrompt),
                InferenceMessage(role: .user, content: input)
            ]
        )

        let subAgentTask = Task { [weak self] in
            guard let self else { return }
            self.updateSubAgent(runID: runID) { current in
                current.status = .running
            }

            do {
                try await client.loadModel(self.model)
                var assembledOutput = ""
                let stream = await client.streamCompletion(request)
                for try await event in stream {
                    switch event {
                    case let .token(token):
                        assembledOutput += token
                        self.updateSubAgent(runID: runID) { current in
                            current.output = assembledOutput
                        }
                    case .completed:
                        self.updateSubAgent(runID: runID) { current in
                            current.status = .completed
                            current.output = assembledOutput
                            current.errorMessage = nil
                        }
                    case .cancelled:
                        self.updateSubAgent(runID: runID) { current in
                            current.status = .cancelled
                            current.errorMessage = "Sub-agent run cancelled."
                        }
                    case .started:
                        continue
                    }
                }
            } catch is CancellationError {
                self.updateSubAgent(runID: runID) { current in
                    current.status = .cancelled
                    current.errorMessage = "Sub-agent run cancelled."
                }
            } catch {
                self.updateSubAgent(runID: runID) { current in
                    current.status = .failed
                    current.errorMessage = error.localizedDescription
                }
            }

            self.subAgentTasks.removeValue(forKey: runID)
        }
        subAgentTasks[runID] = subAgentTask
    }

    func cancelSubAgentRun(_ runID: UUID) {
        guard let task = subAgentTasks[runID] else { return }
        task.cancel()
        subAgentTasks.removeValue(forKey: runID)
        updateSubAgent(runID: runID) { current in
            current.status = .cancelled
            current.errorMessage = "Sub-agent run cancelled."
        }
    }

    func useSubAgentOutput(_ runID: UUID) {
        guard let run = subAgentRuns.first(where: { $0.id == runID }) else { return }
        let safeOutput = String(run.output.prefix(4_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safeOutput.isEmpty else { return }
        userInput = safeOutput
        statusText = "Loaded sub-agent output into input."
    }

    func refreshToolPermissionProfile() {
        toolPermissionProfile = toolPermissionProvider.currentProfile()
    }

    func refreshScheduledState() {
        scheduledJobs = scheduledTaskScheduler.jobs()
        scheduledRunLogs = scheduledTaskScheduler.logs()
        schedulerSummaryText = schedulerSummary(for: scheduledJobs, now: nowProvider())
    }

    private func updateSubAgent(runID: UUID, mutation: (inout SubAgentRun) -> Void) {
        guard let index = subAgentRuns.firstIndex(where: { $0.id == runID }) else { return }
        var copy = subAgentRuns[index]
        mutation(&copy)
        subAgentRuns[index] = copy
    }

    private func permissionEvaluation(for task: AgentTaskTemplate) -> ToolPermissionEvaluation {
        toolPermissionPolicyPipeline.evaluate(
            task: task,
            activeProfile: toolPermissionProfile
        )
    }

    private func requiresApproval(for requiredProfile: AgentToolAccessLevel) -> Bool {
        requiredProfile.rank >= AgentToolAccessLevel.localFiles.rank
    }

    private func presentApprovalPrompt(
        for task: AgentTaskTemplate,
        input: String,
        requiredProfile: AgentToolAccessLevel
    ) {
        let prompt = TaskApprovalPrompt(
            id: UUID(),
            taskID: task.id,
            taskName: task.name,
            reason: "This task requires \(requiredProfile.title) access.",
            expiresAt: nowProvider().addingTimeInterval(approvalTimeout)
        )
        pendingApproval = prompt
        pendingApprovalContext = PendingApprovalContext(task: task, input: input)
        errorMessage = nil
        statusText = "Approval required before running \(task.name)."
    }

    private func clearPendingApproval() {
        pendingApproval = nil
        pendingApprovalContext = nil
    }

    private func approvalShouldExpire() -> Bool {
        guard let pendingApproval else { return false }
        return nowProvider() >= pendingApproval.expiresAt
    }

    private var trimmedInput: String {
        userInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handle(event: InferenceEvent, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }

        switch event {
        case .started:
            statusText = "Running \(activeTaskTemplate?.name ?? "task")..."
        case let .token(token):
            output += token
        case .completed:
            finishRun(
                status: .completed,
                statusText: "\(activeTaskTemplate?.name ?? "Task") completed.",
                requestID: requestID
            )
        case .cancelled:
            finishRun(
                status: .cancelled,
                statusText: "\(activeTaskTemplate?.name ?? "Task") cancelled.",
                requestID: requestID
            )
        }
    }

    private func finishRun(
        status: RunStatus,
        statusText: String,
        errorMessage: String? = nil,
        requestID: UUID
    ) {
        guard isActiveRequest(requestID) else { return }

        let task = activeTaskTemplate
        let taskName = task?.name ?? "Task"
        let input = activeTaskInput
        let run = TaskRun(
            id: UUID(),
            startedAt: activeTaskStartedAt,
            taskID: task?.id ?? "unknown",
            taskName: taskName,
            inputPreview: previewText(input, limit: 80),
            outputPreview: previewText(output, limit: 120),
            status: status
        )
        runHistory.insert(run, at: 0)
        if runHistory.count > 30 {
            runHistory = Array(runHistory.prefix(30))
        }

        let completedScheduledJobID = activeScheduledJobID
        self.statusText = statusText
        self.errorMessage = errorMessage
        self.isRunning = false
        self.streamTask = nil
        self.activeRequestID = nil
        self.activeTaskTemplate = nil
        self.activeTaskInput = ""
        self.activeScheduledJobID = nil

        if let completedScheduledJobID {
            do {
                let schedulerStatus: ScheduledTaskRunStatus = (status == .completed) ? .completed : .failed
                try scheduledTaskScheduler.recordRunResult(
                    jobID: completedScheduledJobID,
                    status: schedulerStatus,
                    message: errorMessage,
                    at: nowProvider()
                )
                refreshScheduledState()
                if status != .cancelled {
                    runDueScheduledJobs()
                }
            } catch {
                schedulerStatusText = "Failed to update scheduled job result: \(error.localizedDescription)"
            }
        }
    }

    private func previewText(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-" }
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "..."
    }

    private func isActiveRequest(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }

    private func schedulerSummary(for jobs: [ScheduledTaskJob], now: Date) -> String {
        guard !jobs.isEmpty else { return "No scheduled jobs." }
        let dueCount = jobs.filter { $0.nextRunAt <= now }.count
        let nextRunAt = jobs.map(\.nextRunAt).min() ?? now
        let nextRunText = nextRunAt.formatted(date: .abbreviated, time: .shortened)
        let jobCount = jobs.count
        let jobLabel = jobCount == 1 ? "job" : "jobs"

        if dueCount > 0 {
            let dueLabel = dueCount == 1 ? "job" : "jobs"
            return "\(dueCount) \(dueLabel) due now • \(jobCount) scheduled \(jobLabel) • next run \(nextRunText)"
        }

        return "\(jobCount) scheduled \(jobLabel) • next run \(nextRunText)"
    }
}

struct TaskWorkspaceView: View {
    @StateObject private var viewModel: TaskWorkspaceViewModel

    init(
        model: InferenceModelDescriptor,
        inferenceClient: any InferenceClient = LocalRuntimeInferenceClient()
    ) {
        _viewModel = StateObject(
            wrappedValue: TaskWorkspaceViewModel(
                inferenceClient: inferenceClient,
                model: model
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            taskSelection
            inputSection
            outputSection
            schedulingSection
            subAgentSection
            historySection
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refreshToolPermissionProfile()
            viewModel.refreshScheduledState()
        }
        .onChange(of: viewModel.selectedTaskID) { _, _ in
            viewModel.refreshToolPermissionProfile()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tasks")
                .font(.largeTitle.bold())
            Text("Run reusable local task templates with your selected model.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Model: \(viewModel.model.displayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var taskSelection: some View {
        GroupBox("Task Template") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Task", selection: $viewModel.selectedTaskID) {
                    ForEach(viewModel.tasks) { task in
                        Text(task.name).tag(task.id)
                    }
                }
                .pickerStyle(.menu)

                if let task = viewModel.selectedTask {
                    Text(task.summary)
                        .foregroundStyle(.secondary)
                    Text(task.inputHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Required tool profile: \(task.requiredToolAccess.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let effectiveProfile = viewModel.selectedTaskEffectiveRequiredProfile {
                        Text("Effective required profile: \(effectiveProfile.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let selectedTaskPolicyExplanation = viewModel.selectedTaskPolicyExplanation {
                        Text("Policy: \(selectedTaskPolicyExplanation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Current profile: \(viewModel.toolPermissionProfile.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !viewModel.hasPermissionForSelectedTask {
                        Text(viewModel.selectedTaskBlockReason ?? "This task is blocked by tool policy. Update profile in Settings.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("Sandbox: \(viewModel.sandboxStatusText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !viewModel.sandboxGuidance.isEmpty {
                        Text("How to unblock: \(viewModel.sandboxGuidance.joined(separator: " | "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !viewModel.sandboxDiagnostics.isEmpty {
                        Text("Sandbox config diagnostics: \(viewModel.sandboxDiagnostics.joined(separator: " | "))")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let prompt = viewModel.pendingApproval {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Approval Required")
                            .font(.headline)
                        Text("\(prompt.taskName): \(prompt.reason)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Choose how to proceed with this risky action.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button("Allow Once") {
                                viewModel.resolvePendingApproval(.allowOnce)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Always Allow") {
                                viewModel.resolvePendingApproval(.alwaysAllow)
                            }
                            .buttonStyle(.bordered)

                            Button("Deny") {
                                viewModel.resolvePendingApproval(.deny)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 10) {
                    Button("Run Task") {
                        viewModel.runSelectedTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRun)

                    Button("Cancel") {
                        viewModel.cancelRun()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canCancel)

                    Button("Clear Output") {
                        viewModel.clearOutput()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRunning || viewModel.output.isEmpty)
                }

                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let errorMessage = viewModel.errorMessage {
                    Text("Error: \(errorMessage)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputSection: some View {
        GroupBox("Input") {
            TextEditor(text: $viewModel.userInput)
                .font(.body)
                .frame(minHeight: 140)
        }
    }

    private var outputSection: some View {
        GroupBox("Output") {
            ScrollView {
                Text(viewModel.output.isEmpty ? "Task output will appear here." : viewModel.output)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 160)
        }
    }

    private var schedulingSection: some View {
        GroupBox("Scheduler") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Schedule Type", selection: $viewModel.scheduleMode) {
                    ForEach(TaskWorkspaceViewModel.ScheduleMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                DatePicker(
                    "First run",
                    selection: $viewModel.scheduledRunAt,
                    displayedComponents: [.date, .hourAndMinute]
                )

                if viewModel.scheduleMode == .recurring {
                    Stepper(
                        "Repeat every \(viewModel.recurringIntervalMinutes) minutes",
                        value: $viewModel.recurringIntervalMinutes,
                        in: 1...1_440
                    )
                }

                HStack(spacing: 10) {
                    Button("Schedule Task") {
                        viewModel.scheduleSelectedTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedTask == nil || viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Run Due Jobs") {
                        viewModel.runDueScheduledJobs()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRunning)

                    Button("Refresh Jobs") {
                        viewModel.refreshScheduledState()
                    }
                    .buttonStyle(.bordered)
                }

                Text(viewModel.schedulerStatusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(viewModel.schedulerSummaryText)
                    .font(.footnote)
                    .foregroundStyle(viewModel.dueScheduledJobCount > 0 ? .orange : .secondary)

                if viewModel.scheduledJobs.isEmpty {
                    Text("No scheduled jobs.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.scheduledJobs.prefix(6))) { job in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(job.taskName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(job.schedule.kind == .oneShot ? "One-shot" : "Recurring")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Next run: \(job.nextRunAt, format: .dateTime.year().month().day().hour().minute())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if job.schedule.kind == .recurring, let interval = job.schedule.intervalMinutes {
                                    Text("Interval: \(interval)m")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Retries: \(job.retryCount)/\(job.maxRetryCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Button("Remove Job", role: .destructive) {
                                    viewModel.removeScheduledJob(job.id)
                                }
                                .buttonStyle(.bordered)
                            }

                            if job.id != viewModel.scheduledJobs.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }

                if !viewModel.scheduledRunLogs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent scheduler runs")
                            .font(.footnote.weight(.semibold))
                        ForEach(Array(viewModel.scheduledRunLogs.prefix(6))) { log in
                            Text(
                                "\(log.taskName) · \(log.status.rawValue) · \(log.timestamp, format: .dateTime.hour().minute().second())"
                            )
                            .font(.caption2)
                            .foregroundStyle(log.status == .completed ? .green : .orange)
                        }
                    }
                }
            }
        }
    }

    private var subAgentSection: some View {
        GroupBox("Sub-agents") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Run Sub-agent") {
                        viewModel.startSubAgentForSelectedTask()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedTask == nil || viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if viewModel.subAgentRuns.isEmpty {
                    Text("No sub-agent runs yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.subAgentRuns.prefix(6))) { run in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(run.taskName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(run.status.rawValue.capitalized)
                                        .font(.caption2)
                                        .foregroundStyle(subAgentStatusColor(run.status))
                                }
                                Text("Input: \(run.inputPreview)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !run.output.isEmpty {
                                    Text("Output: \(previewSubAgentOutput(run.output))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if let errorMessage = run.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                HStack(spacing: 8) {
                                    Button("Use Output") {
                                        viewModel.useSubAgentOutput(run.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(run.output.isEmpty)

                                    Button("Cancel") {
                                        viewModel.cancelSubAgentRun(run.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(run.status != .running && run.status != .queued)
                                }
                            }

                            if run.id != viewModel.subAgentRuns.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var historySection: some View {
        GroupBox("Run History") {
            if viewModel.runHistory.isEmpty {
                Text("No task runs yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.runHistory.prefix(8))) { run in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(run.taskName)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(run.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(statusColor(run.status))
                                Text(run.startedAt, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Input: \(run.inputPreview)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Output: \(run.outputPreview)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if run.id != viewModel.runHistory.prefix(8).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func statusColor(_ status: TaskWorkspaceViewModel.RunStatus) -> Color {
        switch status {
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    private func subAgentStatusColor(_ status: TaskWorkspaceViewModel.SubAgentRunStatus) -> Color {
        switch status {
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        case .queued, .running:
            .secondary
        }
    }

    private func previewSubAgentOutput(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else { return trimmed }
        return String(trimmed.prefix(120)) + "..."
    }
}
#endif
