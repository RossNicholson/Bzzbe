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

    struct GenerationParameters: Equatable {
        let temperature: Double
        let topP: Double
        let topK: Int
        let maxOutputTokens: Int
    }

    enum GenerationPreset: String, CaseIterable, Identifiable {
        case accurate
        case balanced
        case creative
        case custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .accurate:
                return "Accurate"
            case .balanced:
                return "Balanced"
            case .creative:
                return "Creative"
            case .custom:
                return "Custom"
            }
        }

        var parameters: GenerationParameters? {
            switch self {
            case .accurate:
                return GenerationParameters(
                    temperature: 0.2,
                    topP: 0.7,
                    topK: 20,
                    maxOutputTokens: 512
                )
            case .balanced:
                return GenerationParameters(
                    temperature: 0.7,
                    topP: 0.9,
                    topK: 40,
                    maxOutputTokens: 768
                )
            case .creative:
                return GenerationParameters(
                    temperature: 1.1,
                    topP: 0.97,
                    topK: 80,
                    maxOutputTokens: 1024
                )
            case .custom:
                return nil
            }
        }

        static let selectableCases: [GenerationPreset] = [.accurate, .balanced, .creative, .custom]
    }

    @Published var draft: String = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isStreaming: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var commandFeedback: String?
    @Published private(set) var recoveryHint: RecoveryHint?
    @Published private(set) var lastPrompt: String?
    @Published private(set) var activeConversationID: String?
    @Published private(set) var model: InferenceModelDescriptor
    @Published private(set) var selectedPreset: GenerationPreset = .balanced
    @Published private(set) var temperature: Double = 0.7
    @Published private(set) var topP: Double = 0.9
    @Published private(set) var topK: Int = 40
    @Published private(set) var maxOutputTokens: Int = 768

    let temperatureRange: ClosedRange<Double> = 0.0 ... 2.0
    let topPRange: ClosedRange<Double> = 0.0 ... 1.0
    let topKRange: ClosedRange<Int> = 1 ... 200
    let maxOutputTokenRange: ClosedRange<Int> = 128 ... 4096
    private let compactionSummaryHeader = "🧹 Compacted conversation summary"
    private let estimatedCharactersPerToken = 4
    private let compactionKeepRecentMessages = 8
    private let compactionMinimumMessages = 12
    private let compactionSummarySampleSize = 12
    private let compactionSummaryPreviewLimit = 180
    private let autoCompactionThresholdRatio = 0.78

    private let inferenceClient: any InferenceClient
    private let conversationStore: any ConversationStoring
    private let memoryContextProvider: any MemoryContextProviding
    private let onRequestSetupRerun: () -> Void
    private let primaryModel: InferenceModelDescriptor
    private let fallbackModels: [InferenceModelDescriptor]
    private let modelFailoverCooldownSchedule: [TimeInterval] = [60, 300, 900]
    private var streamTask: Task<Void, Never>?
    private var assistantMessageID: UUID?
    private var activeRequestID: UUID?
    private var conversationIDByRequestID: [UUID: String] = [:]
    private var attemptedModelIDsForCurrentPrompt: Set<String> = []
    private var modelFailureCounts: [String: Int] = [:]
    private var modelCooldownUntil: [String: Date] = [:]

    init(
        inferenceClient: any InferenceClient = LocalRuntimeInferenceClient(),
        conversationStore: any ConversationStoring = ChatViewModel.defaultConversationStore(),
        memoryContextProvider: any MemoryContextProviding = FileMemoryContextProvider(),
        onRequestSetupRerun: @escaping () -> Void = {},
        fallbackModels: [InferenceModelDescriptor] = [],
        model: InferenceModelDescriptor = InferenceModelDescriptor(
            identifier: "qwen3:8b",
            displayName: "Qwen 3 8B",
            contextWindow: 32_768
        )
    ) {
        self.inferenceClient = inferenceClient
        self.conversationStore = conversationStore
        self.memoryContextProvider = memoryContextProvider
        self.onRequestSetupRerun = onRequestSetupRerun
        self.model = model
        primaryModel = model
        self.fallbackModels = Self.normalizedFallbackModels(
            fallbackModels,
            primaryModelID: model.identifier
        )

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

    func applyPreset(_ preset: GenerationPreset) {
        guard let parameters = preset.parameters else { return }
        selectedPreset = preset
        temperature = normalizedTemperature(parameters.temperature)
        topP = normalizedTopP(parameters.topP)
        topK = normalizedTopK(parameters.topK)
        maxOutputTokens = normalizedMaxOutputTokens(parameters.maxOutputTokens)
    }

    func setTemperature(_ value: Double) {
        temperature = normalizedTemperature(value)
        refreshPresetSelection()
    }

    func setTopP(_ value: Double) {
        topP = normalizedTopP(value)
        refreshPresetSelection()
    }

    func setTopK(_ value: Int) {
        topK = normalizedTopK(value)
        refreshPresetSelection()
    }

    func setMaxOutputTokens(_ value: Int) {
        maxOutputTokens = normalizedMaxOutputTokens(value)
        refreshPresetSelection()
    }

    func sendDraft() {
        let prompt = trimmedDraft
        guard !prompt.isEmpty else { return }
        draft = ""
        if handleSlashCommand(prompt) {
            return
        }
        send(prompt: prompt, appendUserMessage: true, resetFailoverState: true)
    }

    func retryLastPrompt() {
        guard let lastPrompt else { return }
        send(prompt: lastPrompt, appendUserMessage: true, resetFailoverState: true)
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

    private func send(prompt: String, appendUserMessage: Bool, resetFailoverState: Bool) {
        guard !isStreaming else { return }

        if appendUserMessage {
            maybeRestorePrimaryModel()
        }
        if resetFailoverState {
            attemptedModelIDsForCurrentPrompt = []
        }
        attemptedModelIDsForCurrentPrompt.insert(model.identifier)

        errorMessage = nil
        if appendUserMessage {
            commandFeedback = nil
        }
        recoveryHint = nil
        if appendUserMessage {
            lastPrompt = prompt
            messages.append(.init(role: .user, content: prompt))
            performAutomaticCompactionIfNeeded()
        }

        let request = InferenceRequest(
            model: model,
            messages: inferenceMessages(),
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK
        )
        let pendingAssistant = Message(role: .assistant, content: "")
        messages.append(pendingAssistant)
        assistantMessageID = pendingAssistant.id
        let requestID = UUID()
        activeRequestID = requestID
        isStreaming = true
        if !appendUserMessage, let activeConversationID {
            conversationIDByRequestID[requestID] = activeConversationID
        }

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                if appendUserMessage {
                    await self.persistUserPrompt(prompt, requestID: requestID)
                }

                try await self.inferenceClient.loadModel(self.model)
                let stream = await self.inferenceClient.streamCompletion(request)
                for try await event in stream {
                    self.handle(event: event, requestID: requestID)
                }
                self.finishStreamingIfNeeded(for: requestID, didComplete: true)
            } catch is CancellationError {
                self.finishStreamingIfNeeded(for: requestID, didComplete: false)
            } catch {
                self.failStreaming(error: error, requestID: requestID)
            }
        }
    }

    private func inferenceMessages() -> [InferenceMessage] {
        var contextMessages: [InferenceMessage] = []
        if let memoryMessage = memorySystemMessage() {
            contextMessages.append(memoryMessage)
        }

        contextMessages.append(contentsOf: messages
            .filter { !$0.content.isEmpty }
            .map { message in
                let role: InferenceRole = message.role == .user ? .user : .assistant
                return InferenceMessage(role: role, content: message.content)
            })
        return contextMessages
    }

    private func memorySystemMessage() -> InferenceMessage? {
        let memoryContext = memoryContextProvider.loadContext()
        guard memoryContext.isEnabled else { return nil }

        let trimmedContent = memoryContext.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return nil }

        let clippedContent = String(trimmedContent.prefix(4_000))
        let query = latestUserPromptForMemoryQuery()
        let matchingNotes: [MemoryNote]
        if
            let searchableProvider = memoryContextProvider as? MemoryNoteSearching,
            !query.isEmpty
        {
            matchingNotes = searchableProvider.searchNotes(
                query: query,
                scope: memoryContext.scope,
                limit: 4
            )
        } else {
            matchingNotes = []
        }

        let noteSnippetSection: String
        if matchingNotes.isEmpty {
            noteSnippetSection = ""
        } else {
            let snippetLines = matchingNotes.map { note in
                "- \(note.title): \(String(note.content.prefix(280)))"
            }
            noteSnippetSection = "\nRelevant memory snippets:\n" + snippetLines.joined(separator: "\n")
        }

        let content = """
        Local memory notes for this user (\(memoryContext.scope.title) scope, editable in Settings). Use only when relevant to the request and do not repeat verbatim unless asked:
        \(clippedContent)\(noteSnippetSection)
        """
        return InferenceMessage(role: .system, content: content)
    }

    private func latestUserPromptForMemoryQuery() -> String {
        messages.last(where: { $0.role == .user })?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func handle(event: InferenceEvent, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        switch event {
        case .started:
            return
        case let .token(token):
            appendAssistantToken(token, requestID: requestID)
        case .completed:
            finishStreamingIfNeeded(for: requestID, didComplete: true)
        case .cancelled:
            finishStreamingIfNeeded(for: requestID, didComplete: false)
        }
    }

    private func appendAssistantToken(_ token: String, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }
        guard let assistantMessageID else { return }
        guard let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else { return }
        messages[index].content += token
    }

    private func finishStreamingIfNeeded(for requestID: UUID, didComplete: Bool) {
        guard isActiveRequest(requestID) else { return }

        let pendingAssistantID = assistantMessageID
        persistAssistantMessageIfNeeded(for: requestID, assistantMessageID: pendingAssistantID)
        if didComplete {
            clearModelFailureState(for: model.identifier)
        }

        isStreaming = false
        streamTask = nil
        assistantMessageID = nil
        activeRequestID = nil
    }

    private func failStreaming(error: Error, requestID: UUID) {
        guard isActiveRequest(requestID) else { return }

        if let lastPrompt,
           attemptModelFailoverRetry(after: error, requestID: requestID, prompt: lastPrompt) {
            return
        }

        applyRecoveryState(for: error)
        finishStreamingIfNeeded(for: requestID, didComplete: false)
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
        commandFeedback = nil
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

    private func normalizedTemperature(_ value: Double) -> Double {
        max(temperatureRange.lowerBound, min(temperatureRange.upperBound, value))
    }

    private func normalizedTopP(_ value: Double) -> Double {
        max(topPRange.lowerBound, min(topPRange.upperBound, value))
    }

    private func normalizedTopK(_ value: Int) -> Int {
        max(topKRange.lowerBound, min(topKRange.upperBound, value))
    }

    private func normalizedMaxOutputTokens(_ value: Int) -> Int {
        max(maxOutputTokenRange.lowerBound, min(maxOutputTokenRange.upperBound, value))
    }

    private func refreshPresetSelection() {
        if let matchingPreset = GenerationPreset.selectableCases.first(where: { preset in
            guard let parameters = preset.parameters else { return false }
            return abs(parameters.temperature - temperature) < 0.001
                && abs(parameters.topP - topP) < 0.001
                && parameters.topK == topK
                && parameters.maxOutputTokens == maxOutputTokens
        }) {
            selectedPreset = matchingPreset
        } else {
            selectedPreset = .custom
        }
    }

    private func performAutomaticCompactionIfNeeded() {
        guard model.contextWindow > 0 else { return }

        let thresholdTokens = max(512, Int(Double(model.contextWindow) * autoCompactionThresholdRatio))
        var didCompact = false

        for _ in 0..<3 {
            let estimatedTokens = estimatedContextTokens()
            guard estimatedTokens >= thresholdTokens else { break }
            guard compactCurrentContext(focus: nil) else { break }
            didCompact = true
        }

        if didCompact {
            commandFeedback = "Auto-compacted older context to stay within model limits."
        }
    }

    private func estimatedContextTokens() -> Int {
        let messageTokens = inferenceMessages()
            .reduce(0) { partial, message in
                partial + max(1, message.content.count / estimatedCharactersPerToken)
            }
        return messageTokens + maxOutputTokens
    }

    private func compactCurrentContext(focus: String?) -> Bool {
        let trimmedMessages = messages
            .map { Message(id: $0.id, role: $0.role, content: $0.content.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.content.isEmpty }

        guard trimmedMessages.count >= compactionMinimumMessages else { return false }
        guard trimmedMessages.count > compactionKeepRecentMessages else { return false }

        let compactCount = trimmedMessages.count - compactionKeepRecentMessages
        let messagesToCompact = Array(trimmedMessages.prefix(compactCount))
        let recentMessages = Array(trimmedMessages.suffix(compactionKeepRecentMessages))

        let summary = buildCompactionSummary(from: messagesToCompact, focus: focus)
        guard !summary.isEmpty else { return false }

        messages = [Message(role: .assistant, content: summary)] + recentMessages
        return true
    }

    private func buildCompactionSummary(from messagesToCompact: [Message], focus: String?) -> String {
        let summarizable = messagesToCompact.filter { !$0.content.hasPrefix(compactionSummaryHeader) }
        let sampledMessages = sampleMessagesForCompactionSummary(summarizable)
        let omittedMessagesCount = max(0, summarizable.count - sampledMessages.count)
        let nestedSummaryCount = max(0, messagesToCompact.count - summarizable.count)

        var lines: [String] = [compactionSummaryHeader]
        if let focus {
            let trimmedFocus = focus.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedFocus.isEmpty {
                lines.append("Focus: \(trimmedFocus)")
            }
        }
        lines.append("Replaced \(messagesToCompact.count) older messages.")

        if nestedSummaryCount > 0 {
            lines.append("Merged \(nestedSummaryCount) previous compaction summaries.")
        }

        if sampledMessages.isEmpty {
            lines.append("No additional details were retained from compacted messages.")
            return lines.joined(separator: "\n")
        }

        lines.append("Snapshot of earlier context:")
        for message in sampledMessages {
            let roleLabel = message.role == .user ? "User" : "Assistant"
            lines.append("- \(roleLabel): \(previewCompactionContent(message.content))")
        }

        if omittedMessagesCount > 0 {
            lines.append("- ... \(omittedMessagesCount) more messages omitted.")
        }

        return lines.joined(separator: "\n")
    }

    private func sampleMessagesForCompactionSummary(_ messages: [Message]) -> [Message] {
        guard messages.count > compactionSummarySampleSize else { return messages }
        let leadingCount = compactionSummarySampleSize / 2
        let trailingCount = compactionSummarySampleSize - leadingCount
        return Array(messages.prefix(leadingCount)) + Array(messages.suffix(trailingCount))
    }

    private func previewCompactionContent(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > compactionSummaryPreviewLimit else { return normalized }
        return String(normalized.prefix(compactionSummaryPreviewLimit)) + "..."
    }

    private func maybeRestorePrimaryModel() {
        guard model.identifier != primaryModel.identifier else { return }
        let now = Date()
        if let cooldownUntil = modelCooldownUntil[primaryModel.identifier], cooldownUntil > now {
            return
        }
        model = primaryModel
    }

    private func attemptModelFailoverRetry(after error: Error, requestID: UUID, prompt: String) -> Bool {
        guard shouldAttemptModelFailover(for: error) else {
            return false
        }
        guard let nextModel = nextAvailableFailoverModel() else {
            return false
        }

        let failedModel = model
        markModelFailure(for: failedModel.identifier)
        tearDownRequestForFailover(requestID: requestID)

        model = nextModel
        attemptedModelIDsForCurrentPrompt.insert(nextModel.identifier)
        commandFeedback = "Model failover: switched to \(nextModel.displayName) and retried."
        errorMessage = nil
        recoveryHint = nil

        send(prompt: prompt, appendUserMessage: false, resetFailoverState: false)
        return true
    }

    private func shouldAttemptModelFailover(for error: Error) -> Bool {
        if let runtimeError = error as? LocalRuntimeInferenceError {
            switch runtimeError {
            case .unavailable, .invalidResponseStatus, .invalidResponse:
                return true
            case let .runtime(details):
                if isMissingModelError(details) {
                    return true
                }
                let normalized = details.lowercased()
                return normalized.contains("connection")
                    || normalized.contains("timeout")
                    || normalized.contains("timed out")
                    || normalized.contains("temporar")
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return true
            default:
                return false
            }
        }

        return false
    }

    private func nextAvailableFailoverModel() -> InferenceModelDescriptor? {
        let now = Date()

        for candidate in fallbackModels {
            guard candidate.identifier != model.identifier else { continue }
            guard !attemptedModelIDsForCurrentPrompt.contains(candidate.identifier) else { continue }
            if let cooldownUntil = modelCooldownUntil[candidate.identifier], cooldownUntil > now {
                continue
            }
            return candidate
        }

        return nil
    }

    private func markModelFailure(for modelID: String) {
        let nextFailureCount = (modelFailureCounts[modelID] ?? 0) + 1
        modelFailureCounts[modelID] = nextFailureCount

        let cooldownIndex = min(nextFailureCount - 1, modelFailoverCooldownSchedule.count - 1)
        let cooldownDuration = modelFailoverCooldownSchedule[cooldownIndex]
        modelCooldownUntil[modelID] = Date().addingTimeInterval(cooldownDuration)
    }

    private func clearModelFailureState(for modelID: String) {
        modelFailureCounts[modelID] = nil
        modelCooldownUntil[modelID] = nil
    }

    private func tearDownRequestForFailover(requestID: UUID) {
        if let assistantMessageID,
           let messageIndex = messages.firstIndex(where: { $0.id == assistantMessageID }) {
            messages.remove(at: messageIndex)
        }

        conversationIDByRequestID[requestID] = nil
        isStreaming = false
        streamTask = nil
        assistantMessageID = nil
        activeRequestID = nil
    }

    private func handleSlashCommand(_ input: String) -> Bool {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.hasPrefix("/") else { return false }

        let components = trimmedInput.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let commandToken = components.first?.lowercased() else { return true }
        let args = Array(components.dropFirst())

        switch commandToken {
        case "/help":
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Commands: /help, /new, /compact [focus], /preset <accurate|balanced|creative>, /temperature <0-2>, /top-p <0-1>, /top-k <int>, /max-tokens <int>"
        case "/new":
            startNewConversation()
            commandFeedback = "Started a new conversation."
        case "/compact":
            errorMessage = nil
            recoveryHint = nil
            let focus = args.isEmpty ? nil : args.joined(separator: " ")
            if compactCurrentContext(focus: focus) {
                commandFeedback = "Compacted older context for this conversation."
            } else {
                commandFeedback = "Not enough conversation history to compact yet."
            }
        case "/preset":
            guard let presetName = args.first, let preset = parsePreset(name: presetName) else {
                errorMessage = "Preset command format: /preset <accurate|balanced|creative>"
                recoveryHint = nil
                commandFeedback = nil
                return true
            }
            applyPreset(preset)
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Applied preset: \(preset.title)."
        case "/temperature":
            guard let rawValue = args.first, let value = Double(rawValue) else {
                errorMessage = "Temperature command format: /temperature <0-2>"
                recoveryHint = nil
                commandFeedback = nil
                return true
            }
            setTemperature(value)
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Temperature set to \(String(format: "%.2f", temperature))."
        case "/top-p":
            guard let rawValue = args.first, let value = Double(rawValue) else {
                errorMessage = "Top-p command format: /top-p <0-1>"
                recoveryHint = nil
                commandFeedback = nil
                return true
            }
            setTopP(value)
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Top-p set to \(String(format: "%.2f", topP))."
        case "/top-k":
            guard let rawValue = args.first, let value = Int(rawValue) else {
                errorMessage = "Top-k command format: /top-k <integer>"
                recoveryHint = nil
                commandFeedback = nil
                return true
            }
            setTopK(value)
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Top-k set to \(topK)."
        case "/max-tokens":
            guard let rawValue = args.first, let value = Int(rawValue) else {
                errorMessage = "Max-tokens command format: /max-tokens <integer>"
                recoveryHint = nil
                commandFeedback = nil
                return true
            }
            setMaxOutputTokens(value)
            errorMessage = nil
            recoveryHint = nil
            commandFeedback = "Max output tokens set to \(maxOutputTokens)."
        default:
            return false
        }
        return true
    }

    private func parsePreset(name: String) -> GenerationPreset? {
        switch name.lowercased() {
        case "accurate":
            return .accurate
        case "balanced":
            return .balanced
        case "creative":
            return .creative
        default:
            return nil
        }
    }

    private static func normalizedFallbackModels(
        _ models: [InferenceModelDescriptor],
        primaryModelID: String
    ) -> [InferenceModelDescriptor] {
        var deduplicated: [InferenceModelDescriptor] = []
        var seenIdentifiers: Set<String> = [primaryModelID]

        for model in models {
            guard !seenIdentifiers.contains(model.identifier) else { continue }
            seenIdentifiers.insert(model.identifier)
            deduplicated.append(model)
        }

        return deduplicated
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

    init(
        model: InferenceModelDescriptor = InferenceModelDescriptor(
            identifier: "qwen3:8b",
            displayName: "Qwen 3 8B",
            contextWindow: 32_768
        ),
        fallbackModels: [InferenceModelDescriptor] = [],
        onRequestSetupRerun: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(
                onRequestSetupRerun: onRequestSetupRerun,
                fallbackModels: fallbackModels,
                model: model
            )
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

    private var presetBinding: Binding<ChatViewModel.GenerationPreset> {
        Binding(
            get: { viewModel.selectedPreset },
            set: { viewModel.applyPreset($0) }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { viewModel.temperature },
            set: { viewModel.setTemperature($0) }
        )
    }

    private var topPBinding: Binding<Double> {
        Binding(
            get: { viewModel.topP },
            set: { viewModel.setTopP($0) }
        )
    }

    private var topKBinding: Binding<Int> {
        Binding(
            get: { viewModel.topK },
            set: { viewModel.setTopK($0) }
        )
    }

    private var maxOutputTokenBinding: Binding<Int> {
        Binding(
            get: { viewModel.maxOutputTokens },
            set: { viewModel.setMaxOutputTokens($0) }
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

            generationControls

            if let commandFeedback = viewModel.commandFeedback {
                Text(commandFeedback)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Slash commands: /help, /new, /compact, /preset, /temperature, /top-p, /top-k, /max-tokens")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

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

    private var generationControls: some View {
        GroupBox("Generation") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Preset", selection: presetBinding) {
                    ForEach(ChatViewModel.GenerationPreset.selectableCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                HStack(spacing: 10) {
                    Text("Temp")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: temperatureBinding,
                        in: viewModel.temperatureRange,
                        step: 0.05
                    )
                    Text(viewModel.temperature, format: .number.precision(.fractionLength(2)))
                        .font(.footnote.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    Text("Top-p")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: topPBinding,
                        in: viewModel.topPRange,
                        step: 0.01
                    )
                    Text(viewModel.topP, format: .number.precision(.fractionLength(2)))
                        .font(.footnote.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }

                HStack(spacing: 16) {
                    Stepper(value: topKBinding, in: viewModel.topKRange, step: 1) {
                        Text("Top-k: \(viewModel.topK)")
                            .font(.footnote)
                    }
                    Stepper(value: maxOutputTokenBinding, in: viewModel.maxOutputTokenRange, step: 64) {
                        Text("Max tokens: \(viewModel.maxOutputTokens)")
                            .font(.footnote)
                    }
                }
            }
        }
        .disabled(viewModel.isStreaming)
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
