import CoreAgents
import CoreHardware
import CoreInference
import CoreInstaller
import CoreStorage
import DesignSystem

#if !canImport(SwiftUI)
let gate = PlatformGate()

if !gate.isSupported {
    print("Bzzbe launch blocked: \(gate.unsupportedReason)")
    print("Detected architecture: \(gate.architecture.rawValue)")
} else {
    let hardware = DefaultHardwareProfiler().currentProfile()
    let installerTier = InstallerService().recommendedInstall(for: hardware)
    let taskCount = AgentCatalog().starterTasks().count

    print("\(Theme.appName) scaffold initialized")
    print("Architecture: \(hardware.architecture)")
    print("Recommended tier: \(installerTier.tier)")
    print("Recommended model: \(installerTier.candidate.id)")
    print("Starter tasks: \(taskCount)")

    let inference: InferenceClient = MockInferenceClient()
    let model = InferenceModelDescriptor(identifier: "mock.qwen2.5-3b", displayName: "Mock Qwen 2.5 3B", contextWindow: 32_768)

    do {
        try await inference.loadModel(model)

        let request = InferenceRequest(
            model: model,
            messages: [.init(role: .user, content: "hello")]
        )

        let stream = await inference.streamCompletion(request)
        for try await event in stream {
            if case let .token(token) = event {
                print("Token: \(token)")
            }
        }
    } catch {
        print("Inference stream failed: \(error)")
    }
}
#endif
