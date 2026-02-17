import CoreInference
import Testing

@Test("InferenceRequest normalizes generation options")
func requestNormalization() {
    let model = InferenceModelDescriptor(identifier: "qwen2.5:3b", displayName: "Qwen 2.5 3B", contextWindow: 32_768)
    let request = InferenceRequest(
        model: model,
        messages: [.init(role: .user, content: "Hi")],
        maxOutputTokens: 0,
        temperature: 3.5,
        topP: -0.2,
        topK: -4
    )

    #expect(request.maxOutputTokens == 1)
    #expect(request.temperature == 2.0)
    #expect(request.topP == 0.0)
    #expect(request.topK == 0)
}

@Test("MockInferenceClient emits started and completed events")
func mockClientStreamsLifecycleEvents() async throws {
    let client = MockInferenceClient()
    let model = InferenceModelDescriptor(identifier: "qwen2.5:3b", displayName: "Qwen 2.5 3B", contextWindow: 32_768)
    try await client.loadModel(model)

    let request = InferenceRequest(
        model: model,
        messages: [.init(role: .user, content: "Say hello")]
    )

    var events: [InferenceEvent] = []
    let stream = await client.streamCompletion(request)
    for try await event in stream {
        events.append(event)
    }

    #expect(events.first == .started(modelIdentifier: model.identifier))
    #expect(events.contains(.completed))
}
