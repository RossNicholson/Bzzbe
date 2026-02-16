import Foundation

public struct RuntimeModelImportConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let createPath: String
    public let timeoutSeconds: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        createPath: String = "/api/create",
        timeoutSeconds: TimeInterval = 60 * 15
    ) {
        self.baseURL = baseURL
        self.createPath = createPath
        self.timeoutSeconds = timeoutSeconds
    }
}

public enum RuntimeModelImportEvent: Sendable, Equatable {
    case started(modelID: String)
    case status(String)
    case completed
}

public enum RuntimeModelImportError: Error, Sendable, Equatable {
    case unavailable(String)
    case invalidResponseStatus(Int)
    case runtime(String)
    case invalidResponse
}

extension RuntimeModelImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unavailable(message):
            return "Local runtime unavailable: \(message)"
        case let .invalidResponseStatus(status):
            return "Local runtime returned status \(status) while importing model."
        case let .runtime(message):
            return "Local runtime error while importing model: \(message)"
        case .invalidResponse:
            return "Local runtime returned an invalid import response payload."
        }
    }
}

public protocol RuntimeModelImporting: Sendable {
    func importModel(modelID: String, artifactFileURL: URL) async -> AsyncThrowingStream<RuntimeModelImportEvent, Error>
    func cancelCurrentImport() async
}

public actor OllamaModelImportClient: RuntimeModelImporting {
    private let configuration: RuntimeModelImportConfiguration
    private let urlSession: URLSession
    private var currentTask: Task<Void, Never>?
    private var currentContinuation: AsyncThrowingStream<RuntimeModelImportEvent, Error>.Continuation?

    public init(
        configuration: RuntimeModelImportConfiguration = .init(),
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    public func importModel(modelID: String, artifactFileURL: URL) async -> AsyncThrowingStream<RuntimeModelImportEvent, Error> {
        AsyncThrowingStream { continuation in
            currentContinuation = continuation

            continuation.onTermination = { [weak self] termination in
                guard case .cancelled = termination else { return }
                Task {
                    await self?.cancelCurrentImport()
                }
            }

            currentTask = Task { [weak self] in
                guard let self else { return }

                do {
                    continuation.yield(.started(modelID: modelID))
                    try await self.streamImportRequest(
                        modelID: modelID,
                        artifactFileURL: artifactFileURL,
                        continuation: continuation
                    )
                    continuation.yield(.completed)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }

                await self.clearCurrentImportState()
            }
        }
    }

    public func cancelCurrentImport() async {
        currentTask?.cancel()
        currentTask = nil
        currentContinuation?.finish()
        currentContinuation = nil
    }

    private func streamImportRequest(
        modelID: String,
        artifactFileURL: URL,
        continuation: AsyncThrowingStream<RuntimeModelImportEvent, Error>.Continuation
    ) async throws {
        let createURL = configuration.baseURL.appending(path: trimmedLeadingSlash(configuration.createPath))
        var request = URLRequest(url: createURL)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateModelRequest(
                model: modelID,
                from: artifactFileURL.path
            )
        )

        do {
            let (bytes, response) = try await urlSession.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RuntimeModelImportError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw RuntimeModelImportError.invalidResponseStatus(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            for try await rawLine in bytes.lines {
                try Task.checkCancellation()
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                let payload = try decoder.decode(CreateStreamEnvelope.self, from: Data(line.utf8))

                if let runtimeError = payload.error {
                    throw RuntimeModelImportError.runtime(runtimeError)
                }

                if let status = payload.status, !status.isEmpty {
                    continuation.yield(.status(status))
                }
            }
        } catch let error as RuntimeModelImportError {
            throw error
        } catch {
            throw RuntimeModelImportError.unavailable(error.localizedDescription)
        }
    }

    private func clearCurrentImportState() {
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

private struct CreateModelRequest: Encodable {
    let model: String
    let from: String
    let stream: Bool = true
}

private struct CreateStreamEnvelope: Decodable {
    let status: String?
    let error: String?
}
