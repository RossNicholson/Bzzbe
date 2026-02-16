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

    struct TaskRun: Identifiable, Equatable {
        let id: UUID
        let startedAt: Date
        let taskID: String
        let taskName: String
        let inputPreview: String
        let outputPreview: String
        let status: RunStatus
    }

    @Published private(set) var tasks: [AgentTaskTemplate]
    @Published var selectedTaskID: String
    @Published var userInput: String = ""
    @Published private(set) var output: String = ""
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusText: String = "Choose a task and run it."
    @Published private(set) var errorMessage: String?
    @Published private(set) var runHistory: [TaskRun] = []

    let model: InferenceModelDescriptor

    private let inferenceClient: any InferenceClient
    private var streamTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeTaskTemplate: AgentTaskTemplate?
    private var activeTaskInput: String = ""
    private var activeTaskStartedAt: Date = Date()

    init(
        catalog: AgentCatalog = AgentCatalog(),
        inferenceClient: any InferenceClient = LocalRuntimeInferenceClient(),
        model: InferenceModelDescriptor
    ) {
        let templates = catalog.templates()
        self.tasks = templates
        self.selectedTaskID = templates.first?.id ?? ""
        self.inferenceClient = inferenceClient
        self.model = model
    }

    var selectedTask: AgentTaskTemplate? {
        tasks.first(where: { $0.id == selectedTaskID })
    }

    var canRun: Bool {
        !isRunning && !trimmedInput.isEmpty && selectedTask != nil
    }

    var canCancel: Bool {
        isRunning
    }

    func runSelectedTask() {
        guard !isRunning else { return }
        guard let task = selectedTask else {
            statusText = "No task selected."
            return
        }

        let input = trimmedInput
        guard !input.isEmpty else {
            statusText = "Add input to run this task."
            return
        }

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

        self.statusText = statusText
        self.errorMessage = errorMessage
        self.isRunning = false
        self.streamTask = nil
        self.activeRequestID = nil
        self.activeTaskTemplate = nil
        self.activeTaskInput = ""
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
            historySection
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
}
#endif
