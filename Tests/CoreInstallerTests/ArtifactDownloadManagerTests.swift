import CoreInstaller
import Foundation
import Testing

@Test("ResumableArtifactDownloadManager downloads artifact with progress events")
func downloadsArtifact() async throws {
    let testDirectory = try makeTemporaryDirectory()
    let sourceURL = testDirectory.appendingPathComponent("source.bin")
    let destinationURL = testDirectory.appendingPathComponent("destination.bin")
    try writeSeedFile(to: sourceURL, bytes: 512 * 1024)

    let manager = ResumableArtifactDownloadManager(chunkSize: 32 * 1024)
    let request = ArtifactDownloadRequest(id: "download.full", sourceURL: sourceURL, destinationURL: destinationURL)

    var started = false
    var completed = false
    var previousBytes: Int64 = 0

    let stream = manager.startDownload(request)
    for try await event in stream {
        switch event {
        case let .started(resumedBytes, totalBytes):
            started = true
            #expect(resumedBytes == 0)
            #expect(totalBytes > 0)
        case let .progress(bytesWritten, totalBytes):
            #expect(bytesWritten >= previousBytes)
            #expect(bytesWritten <= totalBytes)
            previousBytes = bytesWritten
        case let .completed(url, totalBytes):
            completed = true
            #expect(url == destinationURL)
            #expect(totalBytes == previousBytes)
        }
    }

    #expect(started)
    #expect(completed)
    #expect(try Data(contentsOf: sourceURL) == Data(contentsOf: destinationURL))
}

@Test("ResumableArtifactDownloadManager resumes from partial file after cancellation")
func resumesFromPartialFile() async throws {
    let testDirectory = try makeTemporaryDirectory()
    let sourceURL = testDirectory.appendingPathComponent("resume-source.bin")
    let destinationURL = testDirectory.appendingPathComponent("resume-destination.bin")
    try writeSeedFile(to: sourceURL, bytes: 2 * 1024 * 1024)

    let manager = ResumableArtifactDownloadManager(chunkSize: 16 * 1024)
    let request = ArtifactDownloadRequest(id: "download.resume", sourceURL: sourceURL, destinationURL: destinationURL)

    var interruptedAt: Int64 = 0
    let firstStream = manager.startDownload(request)
    for try await event in firstStream {
        if case let .progress(bytesWritten, _) = event, bytesWritten > 0 {
            interruptedAt = bytesWritten
            manager.cancelDownload(id: request.id)
            break
        }
    }
    #expect(interruptedAt > 0)

    let secondStream = manager.startDownload(request)
    var resumedFrom: Int64 = 0
    var completed = false
    for try await event in secondStream {
        switch event {
        case let .started(resumedBytes, _):
            resumedFrom = resumedBytes
        case .progress:
            continue
        case .completed:
            completed = true
        }
    }

    #expect(resumedFrom > 0)
    #expect(completed)
    #expect(try Data(contentsOf: sourceURL) == Data(contentsOf: destinationURL))
}

@Suite("ResumableArtifactDownloadManager HTTP", .serialized)
struct ArtifactDownloadManagerHTTPTests {
    @Test("ResumableArtifactDownloadManager downloads https artifact")
    func downloadsHTTPSArtifact() async throws {
        let testDirectory = try makeTemporaryDirectory()
        let destinationURL = testDirectory.appendingPathComponent("network-destination.gguf")
        let payload = Data(repeating: 0x2A, count: 256 * 1024)

        let session = makeStubbedHTTPSession(payload: payload)
        let manager = ResumableArtifactDownloadManager(urlSession: session, chunkSize: 16 * 1024)
        let request = ArtifactDownloadRequest(
            id: "network.full",
            sourceURL: URL(string: "https://provider.example/model.gguf")!,
            destinationURL: destinationURL
        )

        var completed = false
        let stream = manager.startDownload(request)
        for try await event in stream {
            if case .completed = event {
                completed = true
            }
        }

        #expect(completed)
        #expect(try Data(contentsOf: destinationURL) == payload)
    }

    @Test("ResumableArtifactDownloadManager resumes https artifact with range request")
    func resumesHTTPSArtifactWithRange() async throws {
        let testDirectory = try makeTemporaryDirectory()
        let destinationURL = testDirectory.appendingPathComponent("network-resume.gguf")
        let payload = Data((0..<(1024 * 1024)).map { UInt8($0 % 251) })

        let session = makeStubbedHTTPSession(payload: payload)
        let manager = ResumableArtifactDownloadManager(urlSession: session, chunkSize: 8 * 1024)
        let request = ArtifactDownloadRequest(
            id: "network.resume",
            sourceURL: URL(string: "https://provider.example/model.gguf")!,
            destinationURL: destinationURL
        )

        var interruptedAt: Int64 = 0
        let firstStream = manager.startDownload(request)
        for try await event in firstStream {
            if case let .progress(bytesWritten, _) = event, bytesWritten > 0 {
                interruptedAt = bytesWritten
                manager.cancelDownload(id: request.id)
                break
            }
        }
        #expect(interruptedAt > 0)

        var resumedFrom: Int64 = 0
        var completed = false
        let secondStream = manager.startDownload(request)
        for try await event in secondStream {
            switch event {
            case let .started(resumedBytes, _):
                resumedFrom = resumedBytes
            case .progress:
                continue
            case .completed:
                completed = true
            }
        }

        #expect(resumedFrom > 0)
        #expect(completed)
        #expect(try Data(contentsOf: destinationURL) == payload)
    }

    private func makeStubbedHTTPSession(payload: Data) -> URLSession {
        HTTPDownloadURLProtocolStub.payload = payload
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPDownloadURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-download-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSeedFile(to url: URL, bytes: Int) throws {
    var data = Data(count: bytes)
    data.withUnsafeMutableBytes { rawBuffer in
        guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
        for index in 0..<rawBuffer.count {
            bytes[index] = UInt8(index % 251)
        }
    }
    try data.write(to: url, options: .atomic)
}

private final class HTTPDownloadURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var payload: Data = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let rangeHeader = request.value(forHTTPHeaderField: "Range")
        let payload = Self.payload

        if let rangeHeader,
           let offset = parseRangeOffset(rangeHeader),
           offset < payload.count {
            let responseData = payload.suffix(from: offset)
            let headers = [
                "Content-Length": "\(responseData.count)",
                "Content-Range": "bytes \(offset)-\(payload.count - 1)/\(payload.count)"
            ]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: nil,
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(responseData))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(payload.count)"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func parseRangeOffset(_ header: String) -> Int? {
        let prefix = "bytes="
        guard header.hasPrefix(prefix) else { return nil }
        let rangeValue = header.dropFirst(prefix.count)
        let parts = rangeValue.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        return Int(first)
    }
}
