import CoreInstaller
import Foundation
import Testing

@Suite("OllamaModelImportClient", .serialized)
struct RuntimeModelImportClientTests {
    @Test("OllamaModelImportClient streams model import status")
    func streamsModelImportStatus() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/create" {
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
            artifactFileURL: URL(fileURLWithPath: "/tmp/qwen.gguf")
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
    }

    @Test("OllamaModelImportClient surfaces runtime import errors")
    func surfacesRuntimeImportErrors() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/create" {
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
            artifactFileURL: URL(fileURLWithPath: "/tmp/broken.gguf")
        )
        var capturedError: Error?
        do {
            for try await _ in stream {}
        } catch {
            capturedError = error
        }

        #expect((capturedError as? RuntimeModelImportError) == .runtime("invalid model file"))
    }

    private func makeStubbedSession(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        ImportURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImportURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
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
