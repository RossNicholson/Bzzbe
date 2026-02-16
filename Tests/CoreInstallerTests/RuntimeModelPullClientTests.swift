import CoreInstaller
import Foundation
import Testing

@Suite("OllamaModelPullClient", .serialized)
struct RuntimeModelPullClientTests {
    @Test("OllamaModelPullClient streams model pull progress")
    func streamsModelPullProgress() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/pull" {
                let payload = """
                {"status":"pulling manifest"}
                {"status":"downloading","total":1000,"completed":250}
                {"status":"downloading","total":1000,"completed":1000}
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

        let client = OllamaModelPullClient(
            configuration: RuntimeModelPullConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let stream = await client.pullModel("qwen3:8b")
        var sawStart = false
        var sawCompleted = false
        var progressSamples: [(Int64, Int64)] = []

        for try await event in stream {
            switch event {
            case let .started(modelID):
                sawStart = modelID == "qwen3:8b"
            case let .progress(completedBytes, totalBytes, _):
                progressSamples.append((completedBytes, totalBytes))
            case .completed:
                sawCompleted = true
            case .status:
                break
            }
        }

        #expect(sawStart)
        #expect(sawCompleted)
        #expect(progressSamples.count == 2)
        #expect(progressSamples[0].0 == 250)
        #expect(progressSamples[0].1 == 1000)
        #expect(progressSamples[1].0 == 1000)
        #expect(progressSamples[1].1 == 1000)
    }

    @Test("OllamaModelPullClient surfaces runtime pull errors")
    func surfacesRuntimePullErrors() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/pull" {
                let payload = """
                {"error":"model not found"}
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

        let client = OllamaModelPullClient(
            configuration: RuntimeModelPullConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let stream = await client.pullModel("missing")
        var capturedError: Error?
        do {
            for try await _ in stream {}
        } catch {
            capturedError = error
        }

        #expect((capturedError as? RuntimeModelPullError) == .runtime("model not found"))
    }

    private func makeStubbedSession(
        handler: @escaping (URLRequest) -> (HTTPURLResponse, Data)
    ) -> URLSession {
        URLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolStub: URLProtocol {
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
