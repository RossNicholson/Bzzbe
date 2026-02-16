#if canImport(SwiftUI)
@testable import BzzbeApp
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

private actor StubTaskInferenceClient: InferenceClient {
    private let events: [InferenceEvent]
    private let loadError: Error?
    private let streamError: Error?

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
        if let loadError {
            throw loadError
        }
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
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
