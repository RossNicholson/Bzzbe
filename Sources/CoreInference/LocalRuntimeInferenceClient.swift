import Foundation

public struct LocalRuntimeConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let chatPath: String
    public let modelProbePath: String
    public let timeoutSeconds: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        chatPath: String = "/api/chat",
        modelProbePath: String = "/api/show",
        timeoutSeconds: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.chatPath = chatPath
        self.modelProbePath = modelProbePath
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum LocalRuntimeInferenceError: Error, Sendable, Equatable {
    case unavailable(String)
    case invalidResponseStatus(Int)
    case runtime(String)
    case invalidResponse
}

extension LocalRuntimeInferenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return "Local runtime unavailable: \(message)"
        case let .invalidResponseStatus(status):
            return "Local runtime returned status \(status)."
        case let .runtime(message):
            return "Local runtime error: \(message)"
        case .invalidResponse:
            return "Local runtime returned an invalid response payload."
        }
    }
}

public actor LocalRuntimeInferenceClient: InferenceClient {
    private let configuration: LocalRuntimeConfiguration
    private let urlSession: URLSession
    private var currentTask: Task<Void, Never>?
    private var currentContinuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation?

    public init(
        configuration: LocalRuntimeConfiguration = .init(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func loadModel(_ model: InferenceModelDescriptor) async throws {
        let url = configuration.baseURL.appending(path: trimmedLeadingSlash(configuration.modelProbePath))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ModelProbeRequest(model: model.identifier))

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LocalRuntimeInferenceError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                if let runtimeError = try? JSONDecoder().decode(RuntimeErrorEnvelope.self, from: data),
                   let message = runtimeError.error {
                    throw LocalRuntimeInferenceError.runtime(message)
                }
                throw LocalRuntimeInferenceError.invalidResponseStatus(httpResponse.statusCode)
            }
        } catch let error as LocalRuntimeInferenceError {
            throw error
        } catch {
            throw LocalRuntimeInferenceError.unavailable(error.localizedDescription)
        }
    }

    public func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            currentContinuation = continuation

            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task {
                    await self?.cancelCurrentRequest()
                }
            }

            currentTask = Task { [weak self] in
                guard let self else { return }

                do {
                    continuation.yield(.started(modelIdentifier: request.model.identifier))
                    try await self.streamCompletionRequest(request, continuation: continuation)
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await self.clearCurrentStreamState()
            }
        }
    }

    public func cancelCurrentRequest() async {
        currentTask?.cancel()
        currentTask = nil
        currentContinuation?.yield(.cancelled)
        currentContinuation?.finish()
        currentContinuation = nil
    }

    private func streamCompletionRequest(
        _ inferenceRequest: InferenceRequest,
        continuation: AsyncThrowingStream<InferenceEvent, Error>.Continuation
    ) async throws {
        let url = configuration.baseURL.appending(path: trimmedLeadingSlash(configuration.chatPath))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(from: inferenceRequest))

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LocalRuntimeInferenceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw LocalRuntimeInferenceError.invalidResponseStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        var sawDone = false
        var thoughtFilter = ThoughtTagFilter()

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let payload = try decoder.decode(StreamEnvelope.self, from: Data(line.utf8))

            if let runtimeError = payload.error {
                throw LocalRuntimeInferenceError.runtime(runtimeError)
            }

            let token = payload.message?.content ?? payload.response
            if let token, !token.isEmpty {
                let visibleToken = thoughtFilter.process(token)
                if !visibleToken.isEmpty {
                    continuation.yield(.token(visibleToken))
                }
            }

            if payload.done {
                let trailingVisibleToken = thoughtFilter.finish()
                if !trailingVisibleToken.isEmpty {
                    continuation.yield(.token(trailingVisibleToken))
                }
                continuation.yield(.completed)
                continuation.finish()
                sawDone = true
                break
            }
        }

        if !sawDone {
            let trailingVisibleToken = thoughtFilter.finish()
            if !trailingVisibleToken.isEmpty {
                continuation.yield(.token(trailingVisibleToken))
            }
            continuation.yield(.completed)
            continuation.finish()
        }
    }

    private func clearCurrentStreamState() {
        currentTask = nil
        currentContinuation = nil
    }

    private func trimmedLeadingSlash(_ value: String) -> String {
        if value.hasPrefix("/") {
            return String(value.dropFirst())
        }
        return value
    }
}

private struct ThoughtTagFilter {
    private static let openingTag = "<think>"
    private static let closingTag = "</think>"
    private static let openingTagLower = openingTag.lowercased()
    private static let closingTagLower = closingTag.lowercased()

    private var buffer: String = ""
    private var isInsideThoughtBlock: Bool = false

    mutating func process(_ fragment: String) -> String {
        guard !fragment.isEmpty else { return "" }
        buffer += fragment

        var output = ""
        while true {
            if isInsideThoughtBlock {
                if let closingRange = buffer.range(of: Self.closingTag, options: .caseInsensitive) {
                    buffer.removeSubrange(buffer.startIndex..<closingRange.upperBound)
                    isInsideThoughtBlock = false
                    continue
                }

                buffer = trailingOverlapSuffix(buffer: buffer, tagLower: Self.closingTagLower)
                break
            }

            if let openingRange = buffer.range(of: Self.openingTag, options: .caseInsensitive) {
                output += String(buffer[..<openingRange.lowerBound])
                buffer.removeSubrange(buffer.startIndex..<openingRange.upperBound)
                isInsideThoughtBlock = true
                continue
            }

            let overlapSuffix = trailingOverlapSuffix(buffer: buffer, tagLower: Self.openingTagLower)
            let trailingCount = overlapSuffix.count
            if trailingCount > 0 {
                output += String(buffer.dropLast(trailingCount))
            } else {
                output += buffer
            }
            buffer = overlapSuffix
            break
        }

        return output
    }

    mutating func finish() -> String {
        if isInsideThoughtBlock {
            buffer = ""
            return ""
        }
        let output = buffer
        buffer = ""
        return output
    }

    private func trailingOverlapSuffix(buffer: String, tagLower: String) -> String {
        guard !buffer.isEmpty else { return "" }
        let maxLength = min(buffer.count, tagLower.count - 1)
        guard maxLength > 0 else { return "" }
        let lowerBuffer = buffer.lowercased()

        for length in stride(from: maxLength, through: 1, by: -1) {
            let suffix = String(lowerBuffer.suffix(length))
            if tagLower.hasPrefix(suffix) {
                return String(buffer.suffix(length))
            }
        }

        return ""
    }
}

private struct ModelProbeRequest: Encodable {
    let model: String
}

private struct RuntimeErrorEnvelope: Decodable {
    let error: String?
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let options: ChatOptions

    init(from request: InferenceRequest) {
        self.model = request.model.identifier
        self.messages = request.messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) }
        self.stream = true
        self.options = ChatOptions(
            temperature: request.temperature,
            numPredict: request.maxOutputTokens
        )
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatOptions: Encodable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct StreamEnvelope: Decodable {
    struct Message: Decodable {
        let content: String?
    }

    let message: Message?
    let response: String?
    let done: Bool
    let error: String?
}
