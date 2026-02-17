import CoreInference
import Foundation
import Testing

@Suite("LocalRuntimeInferenceClient", .serialized)
struct LocalRuntimeInferenceClientTests {
    @Test("LocalRuntimeInferenceClient streams tokens from runtime NDJSON")
    func streamsRuntimeTokens() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/show" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{}".utf8)
                )
            }

            if request.url?.path == "/api/chat" {
                let payload = """
                {"message":{"content":"Hel"},"done":false}
                {"message":{"content":"lo"},"done":false}
                {"done":true}
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

        let client = LocalRuntimeInferenceClient(
            configuration: LocalRuntimeConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let model = InferenceModelDescriptor(identifier: "qwen2.5:7b-instruct-q4_K_M", displayName: "Qwen", contextWindow: 32_768)
        try await client.loadModel(model)

        let request = InferenceRequest(
            model: model,
            messages: [.init(role: .user, content: "hello")]
        )

        var tokens: [String] = []
        var sawStarted = false
        var sawCompleted = false

        let stream = await client.streamCompletion(request)
        for try await event in stream {
            switch event {
            case .started:
                sawStarted = true
            case let .token(token):
                tokens.append(token)
            case .completed:
                sawCompleted = true
            case .cancelled:
                break
            }
        }

        #expect(sawStarted)
        #expect(sawCompleted)
        #expect(tokens.joined() == "Hello")
    }

    @Test("LocalRuntimeInferenceClient surfaces runtime error payloads")
    func surfacesRuntimeErrors() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/show" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{}".utf8)
                )
            }

            if request.url?.path == "/api/chat" {
                let payload = """
                {"error":"model not found","done":true}
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

        let client = LocalRuntimeInferenceClient(
            configuration: LocalRuntimeConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let model = InferenceModelDescriptor(identifier: "missing", displayName: "Missing", contextWindow: 4_096)
        try await client.loadModel(model)

        let request = InferenceRequest(model: model, messages: [.init(role: .user, content: "hello")])
        let stream = await client.streamCompletion(request)

        var capturedError: Error?
        do {
            for try await _ in stream {}
        } catch {
            capturedError = error
        }

        #expect((capturedError as? LocalRuntimeInferenceError) == .runtime("model not found"))
    }

    @Test("LocalRuntimeInferenceClient strips think tags from streamed output")
    func stripsThinkTags() async throws {
        let session = makeStubbedSession { request in
            if request.url?.path == "/api/show" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{}".utf8)
                )
            }

            if request.url?.path == "/api/chat" {
                let payload = """
                {"message":{"content":"<th"},"done":false}
                {"message":{"content":"ink>internal planning"},"done":false}
                {"message":{"content":" text</thi"},"done":false}
                {"message":{"content":"nk>Hello"},"done":false}
                {"message":{"content":" world"},"done":false}
                {"done":true}
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

        let client = LocalRuntimeInferenceClient(
            configuration: LocalRuntimeConfiguration(baseURL: URL(string: "http://127.0.0.1:11434")!),
            urlSession: session
        )

        let model = InferenceModelDescriptor(identifier: "qwen3:8b", displayName: "Qwen 3 8B", contextWindow: 32_768)
        try await client.loadModel(model)

        let request = InferenceRequest(model: model, messages: [.init(role: .user, content: "hi")])
        let stream = await client.streamCompletion(request)

        var tokens: [String] = []
        for try await event in stream {
            if case let .token(token) = event {
                tokens.append(token)
            }
        }

        #expect(tokens.joined() == "Hello world")
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
