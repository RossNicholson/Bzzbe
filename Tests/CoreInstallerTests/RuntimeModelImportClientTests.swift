import CoreInstaller
import Foundation
import Testing

@Suite("OllamaModelImportClient", .serialized)
struct RuntimeModelImportClientTests {
    @Test("OllamaModelImportClient streams model import status")
    func streamsModelImportStatus() async throws {
        let artifactFileURL = try makeArtifactFileURL()
        defer { try? FileManager.default.removeItem(at: artifactFileURL) }
        let expectedDigest = try ArtifactVerifier().checksum(for: artifactFileURL, algorithm: .sha256)

        var sawBlobUpload = false
        var createRequestBody: CreateRequestBody?

        let session = makeStubbedSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/blobs/sha256:\(expectedDigest)" {
                sawBlobUpload = true
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            if path == "/api/create" {
                if let bodyData = requestBodyData(from: request) {
                    createRequestBody = try? JSONDecoder().decode(CreateRequestBody.self, from: bodyData)
                }
                let payload = """
                {"status":"creating model layer"}
                {"status":"writing manifest"}
                {"status":"success"}
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(payload.utf8)
                )
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = OllamaModelImportClient(
            configuration: RuntimeModelImportConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let stream = await client.importModel(
            modelID: "qwen3:8b",
            artifactFileURL: artifactFileURL
        )
        var sawStart = false
        var sawCompleted = false
        var statuses: [String] = []

        for try await event in stream {
            switch event {
            case let .started(modelID):
                sawStart = modelID == "qwen3:8b"
            case let .status(status):
                statuses.append(status)
            case .completed:
                sawCompleted = true
            }
        }

        #expect(sawStart)
        #expect(sawCompleted)
        #expect(statuses.contains("success"))
        #expect(sawBlobUpload)
        #expect(createRequestBody?.model == "qwen3:8b")
        #expect(createRequestBody?.stream == true)
        #expect(createRequestBody?.files.count == 1)
        #expect(createRequestBody?.files.values.first == "sha256:\(expectedDigest)")
        #expect(createRequestBody?.files.keys.first == artifactFileURL.lastPathComponent)
    }

    @Test("OllamaModelImportClient surfaces runtime import errors")
    func surfacesRuntimeImportErrors() async throws {
        let artifactFileURL = try makeArtifactFileURL()
        defer { try? FileManager.default.removeItem(at: artifactFileURL) }
        let expectedDigest = try ArtifactVerifier().checksum(for: artifactFileURL, algorithm: .sha256)

        let session = makeStubbedSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/blobs/sha256:\(expectedDigest)" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }

            if path == "/api/create" {
                let payload = """
                {"error":"invalid model file"}
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(payload.utf8)
                )
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = OllamaModelImportClient(
            configuration: RuntimeModelImportConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let stream = await client.importModel(
            modelID: "broken-model",
            artifactFileURL: artifactFileURL
        )
        var capturedError: Error?
        do {
            for try await _ in stream {}
        } catch {
            capturedError = error
        }

        #expect((capturedError as? RuntimeModelImportError) == .runtime("invalid model file"))
    }

    @Test("OllamaModelImportClient surfaces blob upload errors")
    func surfacesBlobUploadErrors() async throws {
        let artifactFileURL = try makeArtifactFileURL()
        defer { try? FileManager.default.removeItem(at: artifactFileURL) }
        let expectedDigest = try ArtifactVerifier().checksum(for: artifactFileURL, algorithm: .sha256)

        let session = makeStubbedSession { request in
            let path = request.url?.path ?? ""
            if path == "/api/blobs/sha256:\(expectedDigest)" {
                let payload = """
                {"error":"blob upload rejected"}
                """
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                    Data(payload.utf8)
                )
            }

            return (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }

        let client = OllamaModelImportClient(
            configuration: RuntimeModelImportConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let stream = await client.importModel(
            modelID: "broken-model",
            artifactFileURL: artifactFileURL
        )
        var capturedError: Error?
        do {
            for try await _ in stream {}
        } catch {
            capturedError = error
        }

        #expect((capturedError as? RuntimeModelImportError) == .runtime("blob upload rejected"))
    }

    private func makeArtifactFileURL() throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-import-test-\(UUID().uuidString).gguf", isDirectory: false)
        try Data("fake-gguf-test-payload".utf8).write(to: fileURL)
        return fileURL
    }

    private func makeStubbedSession(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ImportURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImportURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func requestBodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let readCount = stream.read(&buffer, maxLength: buffer.count)
            if readCount < 0 {
                return nil
            }
            if readCount == 0 {
                break
            }
            data.append(buffer, count: readCount)
        }
        return data
    }
}

private struct CreateRequestBody: Decodable {
    let model: String
    let files: [String: String]
    let stream: Bool
}

private final class ImportURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
