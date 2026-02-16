#if canImport(SwiftUI)
import CoreInference
import CoreStorage
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

    struct RecoveryHint: Equatable {
        enum Action: Equatable {
            case retryLastPrompt
            case rerunSetup
        }

        let message: String
        let actionTitle: String
        let action: Action
    }

    @Published var draft: String = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var recoveryHint: RecoveryHint?
    @Published private(set) var lastPrompt: String?
    @Published private(set) var activeConversationID: String?

    let model: InferenceModelDescriptor

    private let inferenceClient: any InferenceClient
    private let conversationStore: any ConversationStoring
    private let onRequestSetupRerun: () -> Void
    private var streamTask: Task<Void, Never>?
    private var assistantMessageID: UUID?
    private var activeRequestID: UUID?
    private var conversationIDByRequestID: [UUID: String] = [:]

    init(
        inferenceClient: any InferenceClient = LocalRuntimeInferenceClient(),
        conversationStore: any ConversationStoring = ChatViewModel.defaultConversationStore(),
        onRequestSetupRerun: @escaping () -> Void = {},
        model: InferenceModelDescriptor = InferenceModelDescriptor(
            identifier: "qwen3:8b",
            displayName: "Qwen 3 8B",
            contextWindow: 32_768
        )
    ) {
        self.inferenceClient = inferenceClient
        self.conversationStore = conversationStore
        self.onRequestSetupRerun = onRequestSetupRerun
        self.model = model

        Task {
            await restoreLatestConversationIfAvailable()
        }
    }

    var canSend: Bool {
        !isStreaming && !trimmedDraft.isEmpty
    }

    var canRetry: Bool {
        !isStreaming && lastPrompt != nil
    }

    var canDeleteActiveConversation: Bool {
        !isStreaming && activeConversationID != nil
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

        let requestID = activeRequestID
        let pendingAssistantID = assistantMessageID
        if let requestID {
            persistAssistantMessageIfNeeded(for: requestID, assistantMessageID: pendingAssistantID)
        }

        if let requestID {
            conversationIDByRequestID[requestID] = nil
        }
        activeRequestID = nil
        assistantMessageID = nil
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false

        Task {
            await inferenceClient.cancelCurrentRequest()
        }
    }

    func startNewConversation() {
        guard !isStreaming else { return }
        draft = ""
        activeConversationID = nil
        messages.removeAll()
        assistantMessageID = nil
        activeRequestID = nil
        conversationIDByRequestID.removeAll()
        lastPrompt = nil
        errorMessage = nil
        recoveryHint = nil
    }

    func performRecoveryAction() {
        guard let recoveryHint else { return }
        switch recoveryHint.action {
        case .retryLastPrompt:
            retryLastPrompt()
        case .rerunSetup:
            onRequestSetupRerun()
        }
    }

    func selectConversation(id: String) {
        guard !isStreaming else { return }
        guard id != activeConversationID else { return }

        Task {
            await loadConversation(id: id)
        }
    }

    func deleteActiveConversation() {
        guard let activeConversationID else { return }
        deleteConversation(id: activeConversationID)
    }

    func deleteConversation(id: String) {
        guard !isStreaming else { return }

        Task {
            await performDeleteConversation(id: id)
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(prompt: String) {
        guard !isStreaming else { return }

        errorMessage = nil
        recoveryHint = nil
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
                await self.persistUserPrompt(prompt, requestID: requestID)

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

        let pendingAssistantID = assistantMessageID
        persistAssistantMessageIfNeeded(for: requestID, assistantMessageID: pendingAssistantID)

        isStreaming = false
        streamTask = nil
        assistantMessageID = nil
        activeRequestID = nil
    }

    private func failStreaming(error: Error, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        applyRecoveryState(for: error)
        finishStreamingIfNeeded(for: requestID)
    }

    private func isActiveRequest(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }

    private func persistUserPrompt(_ prompt: String, requestID: UUID) async {
        do {
            let conversationID = try await ensureConversationID(forPrompt: prompt)
            conversationIDByRequestID[requestID] = conversationID
            _ = try await conversationStore.addMessage(
                conversationID: conversationID,
                role: .user,
                content: prompt
            )
            try? await refreshConversations()
        } catch {
            errorMessage = "Failed to save conversation. \(error.localizedDescription)"
        }
    }

    private func ensureConversationID(forPrompt prompt: String) async throws -> String {
        if let activeConversationID {
            return activeConversationID
        }

        let createdConversation = try await conversationStore.createConversation(title: conversationTitle(from: prompt))
        activeConversationID = createdConversation.id
        try? await refreshConversations()
        return createdConversation.id
    }

    private func persistAssistantMessageIfNeeded(for requestID: UUID, assistantMessageID: UUID?) {
        guard let conversationID = conversationIDByRequestID[requestID] else { return }
        defer { conversationIDByRequestID[requestID] = nil }

        guard let assistantMessageID else { return }
        guard let assistantMessage = messages.first(where: { $0.id == assistantMessageID }) else { return }
        let trimmedContent = assistantMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        Task {
            do {
                _ = try await conversationStore.addMessage(
                    conversationID: conversationID,
                    role: .assistant,
                    content: trimmedContent
                )
                try? await refreshConversations()
            } catch {
                errorMessage = "Failed to save conversation. \(error.localizedDescription)"
            }
        }
    }

    private func restoreLatestConversationIfAvailable() async {
        do {
            try await refreshConversations()
            guard messages.isEmpty else { return }
            guard let latestConversation = conversations.first else { return }
            await loadConversation(id: latestConversation.id)
        } catch {
            errorMessage = "Failed to restore previous conversation. \(error.localizedDescription)"
        }
    }

    private func performDeleteConversation(id: String) async {
        do {
            try await conversationStore.deleteConversation(id: id)

            conversationIDByRequestID = conversationIDByRequestID.filter { $0.value != id }
            let deletedActiveConversation = activeConversationID == id
            if deletedActiveConversation {
                activeConversationID = nil
                messages.removeAll()
                assistantMessageID = nil
                lastPrompt = nil
            }

            try await refreshConversations()

            if deletedActiveConversation, let nextConversationID = conversations.first?.id {
                await loadConversation(id: nextConversationID)
            }
        } catch {
            errorMessage = "Failed to delete conversation. \(error.localizedDescription)"
        }
    }

    private func loadConversation(id: String) async {
        do {
            let storedMessages = try await conversationStore.listMessages(conversationID: id)
            activeConversationID = id
            messages = storedMessages.map(chatMessage(from:))
            lastPrompt = latestUserPrompt(in: storedMessages)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load conversation history. \(error.localizedDescription)"
        }
    }

    private func refreshConversations() async throws {
        conversations = try await conversationStore.listConversations()
    }

    private func chatMessage(from message: ConversationMessage) -> Message {
        let role: Message.Role
        switch message.role {
        case .user:
            role = .user
        case .assistant, .system:
            role = .assistant
        }

        return Message(role: role, content: message.content)
    }

    private func conversationTitle(from prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        guard firstLine.count > 60 else { return firstLine.isEmpty ? "New Conversation" : firstLine }
        return String(firstLine.prefix(60))
    }

    private func latestUserPrompt(in messages: [ConversationMessage]) -> String? {
        messages.reversed().first(where: { $0.role == .user })?.content
    }

    private func applyRecoveryState(for error: Error) {
        if let runtimeError = error as? LocalRuntimeInferenceError {
            switch runtimeError {
            case .unavailable:
                errorMessage = runtimeError.localizedDescription
                recoveryHint = RecoveryHint(
                    message: "Start your local runtime, then retry this prompt.",
                    actionTitle: "Retry Request",
                    action: .retryLastPrompt
                )
                return
            case let .runtime(details):
                if isMissingModelError(details) {
                    errorMessage = "The selected model is missing from the local runtime."
                    recoveryHint = RecoveryHint(
                        message: "Re-run setup to reinstall the recommended model profile.",
                        actionTitle: "Run Setup Again",
                        action: .rerunSetup
                    )
                } else {
                    errorMessage = runtimeError.localizedDescription
                    recoveryHint = RecoveryHint(
                        message: "Retry the request. If this repeats, restart the local runtime.",
                        actionTitle: "Retry Request",
                        action: .retryLastPrompt
                    )
                }
                return
            case .invalidResponseStatus, .invalidResponse:
                errorMessage = runtimeError.localizedDescription
                recoveryHint = RecoveryHint(
                    message: "Retry the request. If this repeats, restart the local runtime.",
                    actionTitle: "Retry Request",
                    action: .retryLastPrompt
                )
                return
            }
        }

        errorMessage = "Generation failed. \(error.localizedDescription)"
        recoveryHint = RecoveryHint(
            message: "Retry the request. If this repeats, restart Bzzbe and the local runtime.",
            actionTitle: "Retry Request",
            action: .retryLastPrompt
        )
    }

    private func isMissingModelError(_ details: String) -> Bool {
        let normalized = details.lowercased()
        return normalized.contains("not found")
            || normalized.contains("no such model")
            || normalized.contains("unknown model")
    }

    private static func defaultConversationStore() -> any ConversationStoring {
        if let sqliteStore = try? SQLiteConversationStore.defaultStore() {
            return sqliteStore
        }
        return InMemoryConversationStore()
    }
}

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel

    init(onRequestSetupRerun: @escaping () -> Void = {}) {
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(onRequestSetupRerun: onRequestSetupRerun)
        )
    }

    var body: some View {
        HSplitView {
            historyPanel
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
            chatPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("History")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.startNewConversation()
                } label: {
                    Label("New Conversation", systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Start a new conversation")
                .disabled(viewModel.isStreaming)
            }

            List(selection: selectedConversationBinding) {
                if viewModel.conversations.isEmpty {
                    Text("No saved conversations yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(viewModel.conversations, id: \.id) { conversation in
                        ConversationRow(conversation: conversation)
                            .tag(Optional(conversation.id))
                            .contextMenu {
                                Button("Delete Conversation", role: .destructive) {
                                    viewModel.deleteConversation(id: conversation.id)
                                }
                                .disabled(viewModel.isStreaming)
                            }
                    }
                }
            }
            .listStyle(.sidebar)

            Button(role: .destructive) {
                viewModel.deleteActiveConversation()
            } label: {
                Label("Delete Selected", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!viewModel.canDeleteActiveConversation)
        }
        .padding(12)
    }

    private var chatPanel: some View {
        VStack(spacing: 12) {
            header
            Divider()
            messageList
            recoverySection
            composer
        }
        .padding(20)
    }

    @ViewBuilder
    private var recoverySection: some View {
        if let errorMessage = viewModel.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let recoveryHint = viewModel.recoveryHint {
                    Text(recoveryHint.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(recoveryHint.actionTitle) {
                        viewModel.performRecoveryAction()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isStreaming)
                }
            }
        }
    }

    private var selectedConversationBinding: Binding<String?> {
        Binding(
            get: { viewModel.activeConversationID },
            set: { newConversationID in
                guard let newConversationID else { return }
                viewModel.selectConversation(id: newConversationID)
            }
        )
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

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .lineLimit(2)
                .font(.body.weight(.medium))
            Text(conversation.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
