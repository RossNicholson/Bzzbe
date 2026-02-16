import Foundation

public struct RuntimeModelPullConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let pullPath: String
    public let timeoutSeconds: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        pullPath: String = "/api/pull",
        timeoutSeconds: TimeInterval = 60 * 15
    ) {
        self.baseURL = baseURL
        self.pullPath = pullPath
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum RuntimeModelPullEvent: Sendable, Equatable {
    case started(modelID: String)
    case status(String)
    case progress(completedBytes: Int64, totalBytes: Int64, status: String?)
    case completed
}

public enum RuntimeModelPullError: Error, Sendable, Equatable {
    case unavailable(String)
    case invalidResponseStatus(Int)
    case runtime(String)
    case invalidResponse
}

extension RuntimeModelPullError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return "Local runtime unavailable: \(message)"
        case let .invalidResponseStatus(status):
            return "Local runtime returned status \(status) while pulling model."
        case let .runtime(message):
            return "Local runtime error while pulling model: \(message)"
        case .invalidResponse:
            return "Local runtime returned an invalid pull response payload."
        }
    }
}

public protocol RuntimeModelPulling: Sendable {
    func pullModel(_ modelID: String) async -> AsyncThrowingStream<RuntimeModelPullEvent, Error>
    func cancelCurrentPull() async
}

public actor OllamaModelPullClient: RuntimeModelPulling {
    private let configuration: RuntimeModelPullConfiguration
    private let urlSession: URLSession
    private var currentTask: Task<Void, Never>?
    private var currentContinuation: AsyncThrowingStream<RuntimeModelPullEvent, Error>.Continuation?

    public init(
        configuration: RuntimeModelPullConfiguration = .init(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func pullModel(_ modelID: String) async -> AsyncThrowingStream<RuntimeModelPullEvent, Error> {
        AsyncThrowingStream { continuation in
            currentContinuation = continuation

            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task {
                    await self?.cancelCurrentPull()
                }
            }

            currentTask = Task { [weak self] in
                guard let self else { return }

                do {
                    continuation.yield(.started(modelID: modelID))
                    try await self.streamPullRequest(modelID: modelID, continuation: continuation)
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await self.clearCurrentPullState()
            }
        }
    }

    public func cancelCurrentPull() async {
        currentTask?.cancel()
        currentTask = nil
        currentContinuation?.finish()
        currentContinuation = nil
    }

    private func streamPullRequest(
        modelID: String,
        continuation: AsyncThrowingStream<RuntimeModelPullEvent, Error>.Continuation
    ) async throws {
        let url = configuration.baseURL.appending(path: trimmedLeadingSlash(configuration.pullPath))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequestBody(name: modelID))

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RuntimeModelPullError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RuntimeModelPullError.invalidResponseStatus(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            for try await rawLine in bytes.lines {
                try Task.checkCancellation()
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }

                let payload = try decoder.decode(PullStreamEnvelope.self, from: Data(line.utf8))
                if let runtimeError = payload.error {
                    throw RuntimeModelPullError.runtime(runtimeError)
                }

                if let completed = payload.completed,
                   let total = payload.total,
                   total > 0 {
                    continuation.yield(
                        .progress(
                            completedBytes: completed,
                            totalBytes: total,
                            status: payload.status
                        )
                    )
                } else if let status = payload.status {
                    continuation.yield(.status(status))
                }
            }
        } catch let error as RuntimeModelPullError {
            throw error
        } catch {
            throw RuntimeModelPullError.unavailable(error.localizedDescription)
        }
    }

    private func clearCurrentPullState() {
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

private struct PullRequestBody: Encodable {
    let name: String
    let stream: Bool = true
}

private struct PullStreamEnvelope: Decodable {
    let status: String?
    let error: String?
    let total: Int64?
    let completed: Int64?
}
