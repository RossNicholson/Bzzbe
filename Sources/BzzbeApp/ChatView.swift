#if canImport(SwiftUI)
import CoreInference
import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    struct Message: Identifiable, Equatable {
        enum Role: Equatable {
            case user
            case assistant
        }

        let id: UUID
        let role: Role
        var content: String

        init(id: UUID = UUID(), role: Role, content: String) {
            self.id = id
            self.role = role
            self.content = content
        }
    }

    @Published var draft: String = ""
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastPrompt: String?

    let model: InferenceModelDescriptor

    private let inferenceClient: any InferenceClient
    private var streamTask: Task<Void, Never>?
    private var assistantMessageID: UUID?
    private var activeRequestID: UUID?

    init(
        inferenceClient: any InferenceClient = MockInferenceClient(),
        model: InferenceModelDescriptor = InferenceModelDescriptor(
            identifier: "mock.qwen2.5-3b",
            displayName: "Mock Qwen 2.5 3B",
            contextWindow: 32_768
        )
    ) {
        self.inferenceClient = inferenceClient
        self.model = model
    }

    var canSend: Bool {
        !isStreaming && !trimmedDraft.isEmpty
    }

    var canRetry: Bool {
        !isStreaming && lastPrompt != nil
    }

    func sendDraft() {
        let prompt = trimmedDraft
        guard !prompt.isEmpty else { return }
        draft = ""
        send(prompt: prompt)
    }

    func retryLastPrompt() {
        guard let lastPrompt else { return }
        send(prompt: lastPrompt)
    }

    func stopStreaming() {
        guard isStreaming else { return }
        activeRequestID = nil
        assistantMessageID = nil
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false

        Task {
            await inferenceClient.cancelCurrentRequest()
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(prompt: String) {
        guard !isStreaming else { return }

        errorMessage = nil
        lastPrompt = prompt
        messages.append(.init(role: .user, content: prompt))

        let request = InferenceRequest(model: model, messages: inferenceMessages())
        let pendingAssistant = Message(role: .assistant, content: "")
        messages.append(pendingAssistant)
        assistantMessageID = pendingAssistant.id
        let requestID = UUID()
        activeRequestID = requestID
        isStreaming = true

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.inferenceClient.loadModel(self.model)
                let stream = await self.inferenceClient.streamCompletion(request)
                for try await event in stream {
                    self.handle(event: event, requestID: requestID)
                }
                self.finishStreamingIfNeeded(for: requestID)
            } catch is CancellationError {
                self.finishStreamingIfNeeded(for: requestID)
            } catch {
                self.failStreaming(error: error, requestID: requestID)
            }
        }
    }

    private func inferenceMessages() -> [InferenceMessage] {
        messages
            .filter { !$0.content.isEmpty }
            .map { message in
                let role: InferenceRole = message.role == .user ? .user : .assistant
                return InferenceMessage(role: role, content: message.content)
            }
    }

    private func handle(event: InferenceEvent, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        switch event {
        case .started:
            return
        case let .token(token):
            appendAssistantToken(token, requestID: requestID)
        case .completed:
            finishStreamingIfNeeded(for: requestID)
        case .cancelled:
            finishStreamingIfNeeded(for: requestID)
        }
    }

    private func appendAssistantToken(_ token: String, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        guard let assistantMessageID else { return }
        guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
        messages[index].content += token
    }

    private func finishStreamingIfNeeded(for requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        isStreaming = false
        streamTask = nil
        assistantMessageID = nil
        activeRequestID = nil
    }

    private func failStreaming(error: Error, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        errorMessage = "Generation failed. \(error.localizedDescription)"
        finishStreamingIfNeeded(for: requestID)
    }

    private func isActiveRequest(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }
}

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 12) {
            header
            Divider()
            messageList
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Chat")
                .font(.largeTitle.bold())
            Text("Streaming local chat over the inference abstraction.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Model: \(viewModel.model.displayName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: viewModel.messages.last?.id) { _, messageID in
                guard let messageID else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(messageID, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No messages yet")
                .font(.headline)
            Text("Send a prompt to start a streaming response.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextField("Type a prompt...", text: $viewModel.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isStreaming)

            HStack(spacing: 8) {
                Button("Send") {
                    viewModel.sendDraft()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!viewModel.canSend)

                Button("Stop") {
                    viewModel.stopStreaming()
                }
                .disabled(!viewModel.isStreaming)

                Button("Retry") {
                    viewModel.retryLastPrompt()
                }
                .disabled(!viewModel.canRetry)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatViewModel.Message

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .assistant {
                bubble
                Spacer(minLength: 60)
            } else {
                Spacer(minLength: 60)
                bubble
            }
        }
        .padding(.horizontal, 12)
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(roleTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(message.content.isEmpty ? "..." : message.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: 480, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var roleTitle: String {
        message.role == .user ? "You" : "Assistant"
    }

    private var backgroundColor: Color {
        message.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12)
    }
}
#endif
