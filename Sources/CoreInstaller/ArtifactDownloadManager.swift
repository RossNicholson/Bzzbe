import Foundation

public struct ArtifactDownloadRequest: Sendable, Equatable {
    public let id: String
    public let sourceURL: URL
    public let destinationURL: URL

    public init(id: String, sourceURL: URL, destinationURL: URL) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
    }
}

public enum ArtifactDownloadEvent: Sendable, Equatable {
    case started(resumedBytes: Int64, totalBytes: Int64)
    case progress(bytesWritten: Int64, totalBytes: Int64)
    case completed(destinationURL: URL, totalBytes: Int64)
}

public enum ArtifactDownloadError: Error, Sendable, Equatable {
    case invalidChunkSize
    case unsupportedSourceScheme(String)
    case sourceNotFound
    case corruptedResumeState
}

public protocol ArtifactDownloading: Sendable {
    func startDownload(_ request: ArtifactDownloadRequest) -> AsyncThrowingStream<ArtifactDownloadEvent, Error>
    func cancelDownload(id: String)
}

public final class ResumableArtifactDownloadManager: @unchecked Sendable, ArtifactDownloading {
    private let fileManager: FileManager
    private let chunkSize: Int
    private let lock = NSLock()
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var continuations: [String: AsyncThrowingStream<ArtifactDownloadEvent, Error>.Continuation] = [:]
    private var activeTokens: [String: UUID] = [:]

    public init(
        fileManager: FileManager = .default,
        chunkSize: Int = 64 * 1024
    ) {
        self.fileManager = fileManager
        self.chunkSize = chunkSize
    }

    public func startDownload(_ request: ArtifactDownloadRequest) -> AsyncThrowingStream<ArtifactDownloadEvent, Error> {
        AsyncThrowingStream { [weak self] continuation in
            guard let self else {
                continuation.finish(throwing: CancellationError())
                return
            }

            let token = UUID()
            let previousTask = replaceContinuation(continuation, token: token, for: request.id)
            previousTask?.cancel()

            continuation.onTermination = { [weak self] _ in
                self?.cancelDownload(id: request.id, onlyIfToken: token)
            }

            let task = Task { [weak self] in
                guard let self else { return }
                await self.runDownload(request, token: token)
            }
            setTask(task, for: request.id)
        }
    }

    public func cancelDownload(id: String) {
        cancelDownload(id: id, onlyIfToken: nil)
    }

    private func cancelDownload(id: String, onlyIfToken token: UUID?) {
        guard let context = removeActiveContext(for: id, matching: token) else { return }
        context.task?.cancel()
        context.continuation?.finish()
    }

    public func partialFileURL(for request: ArtifactDownloadRequest) -> URL {
        Self.partialFileURL(for: request.destinationURL)
    }

    private struct ActiveContext {
        let task: Task<Void, Never>?
        let continuation: AsyncThrowingStream<ArtifactDownloadEvent, Error>.Continuation?
        let token: UUID?
    }

    private func replaceContinuation(
        _ continuation: AsyncThrowingStream<ArtifactDownloadEvent, Error>.Continuation,
        token: UUID,
        for id: String
    ) -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }

        let previousTask = activeTasks[id]
        activeTasks[id] = nil

        if let previousContinuation = continuations.removeValue(forKey: id) {
            previousContinuation.finish()
        }
        continuations[id] = continuation
        activeTokens[id] = token
        return previousTask
    }

    private func setTask(_ task: Task<Void, Never>, for id: String) {
        lock.lock()
        defer { lock.unlock() }
        activeTasks[id] = task
    }

    private func continuation(
        for id: String,
        matching token: UUID
    ) -> AsyncThrowingStream<ArtifactDownloadEvent, Error>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        guard activeTokens[id] == token else { return nil }
        return continuations[id]
    }

    private func removeActiveContext(
        for id: String,
        matching token: UUID?
    ) -> ActiveContext? {
        lock.lock()
        defer { lock.unlock() }
        if let token, activeTokens[id] != token {
            return nil
        }
        let context = ActiveContext(
            task: activeTasks.removeValue(forKey: id),
            continuation: continuations.removeValue(forKey: id),
            token: activeTokens.removeValue(forKey: id)
        )
        return context
    }

    private func emit(_ event: ArtifactDownloadEvent, for id: String, token: UUID) {
        continuation(for: id, matching: token)?.yield(event)
    }

    private func finish(id: String, token: UUID, throwing error: Error? = nil) {
        guard let context = removeActiveContext(for: id, matching: token) else { return }
        if let error {
            context.continuation?.finish(throwing: error)
        } else {
            context.continuation?.finish()
        }
        context.task?.cancel()
    }

    private func runDownload(_ request: ArtifactDownloadRequest, token: UUID) async {
        do {
            guard chunkSize > 0 else {
                throw ArtifactDownloadError.invalidChunkSize
            }
            guard request.sourceURL.isFileURL else {
                throw ArtifactDownloadError.unsupportedSourceScheme(request.sourceURL.scheme ?? "unknown")
            }
            guard fileManager.fileExists(atPath: request.sourceURL.path) else {
                throw ArtifactDownloadError.sourceNotFound
            }

            try ensureDirectoryExists(for: request.destinationURL)

            let totalBytes = try fileSize(at: request.sourceURL)
            let partialURL = Self.partialFileURL(for: request.destinationURL)
            var resumedBytes = fileSizeIfExists(at: partialURL)

            if resumedBytes > totalBytes {
                try? fileManager.removeItem(at: partialURL)
                resumedBytes = 0
            }

            emit(.started(resumedBytes: resumedBytes, totalBytes: totalBytes), for: request.id, token: token)

            if resumedBytes == totalBytes {
                try finalizeDownload(partialURL: partialURL, destinationURL: request.destinationURL)
                emit(.completed(destinationURL: request.destinationURL, totalBytes: totalBytes), for: request.id, token: token)
                finish(id: request.id, token: token)
                return
            }

            try await copyFromSourceFile(
                sourceURL: request.sourceURL,
                partialURL: partialURL,
                requestID: request.id,
                token: token,
                startOffset: resumedBytes,
                totalBytes: totalBytes
            )

            try finalizeDownload(partialURL: partialURL, destinationURL: request.destinationURL)
            emit(.completed(destinationURL: request.destinationURL, totalBytes: totalBytes), for: request.id, token: token)
            finish(id: request.id, token: token)
        } catch is CancellationError {
            finish(id: request.id, token: token)
        } catch {
            finish(id: request.id, token: token, throwing: error)
        }
    }

    private func copyFromSourceFile(
        sourceURL: URL,
        partialURL: URL,
        requestID: String,
        token: UUID,
        startOffset: Int64,
        totalBytes: Int64
    ) async throws {
        if !fileManager.fileExists(atPath: partialURL.path) {
            fileManager.createFile(atPath: partialURL.path, contents: nil)
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        let destinationHandle = try FileHandle(forWritingTo: partialURL)
        defer {
            try? sourceHandle.close()
            try? destinationHandle.close()
        }

        try sourceHandle.seek(toOffset: UInt64(startOffset))
        try destinationHandle.seekToEnd()

        var bytesWritten = startOffset
        while true {
            try Task.checkCancellation()

            guard let data = try sourceHandle.read(upToCount: chunkSize), !data.isEmpty else {
                break
            }

            try destinationHandle.write(contentsOf: data)
            bytesWritten += Int64(data.count)
            emit(.progress(bytesWritten: bytesWritten, totalBytes: totalBytes), for: requestID, token: token)

            await Task.yield()
        }
    }

    private func ensureDirectoryExists(for destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw ArtifactDownloadError.corruptedResumeState
        }
        return Int64(size)
    }

    private func fileSizeIfExists(at url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        return (try? fileSize(at: url)) ?? 0
    }

    private func finalizeDownload(partialURL: URL, destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        guard fileManager.fileExists(atPath: partialURL.path) else {
            throw ArtifactDownloadError.corruptedResumeState
        }
        try fileManager.moveItem(at: partialURL, to: destinationURL)
    }

    public static func partialFileURL(for destinationURL: URL) -> URL {
        destinationURL.appendingPathExtension("part")
    }
}
