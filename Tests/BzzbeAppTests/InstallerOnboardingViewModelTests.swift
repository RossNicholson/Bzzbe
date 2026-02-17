#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreHardware
import CoreInference
import CoreInstaller
import Foundation
import Testing

@MainActor
@Test("InstallerOnboardingViewModel defaults to hardware recommendation")
func installerOnboardingDefaultsToRecommendation() {
    let small = ModelCandidate(
        id: "small",
        displayName: "Small",
        approximateDownloadSizeGB: 2.0,
        minimumMemoryGB: 8,
        tier: .small
    )
    let balanced = ModelCandidate(
        id: "balanced",
        displayName: "Balanced",
        approximateDownloadSizeGB: 5.0,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: balanced.tier.rawValue,
        candidate: balanced,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [small, balanced]
    )
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8)

    let viewModel = InstallerOnboardingViewModel(profile: profile, installerService: service)

    #expect(viewModel.selectedCandidateID == balanced.id)
    #expect(viewModel.selectedCandidate?.id == balanced.id)
    #expect(viewModel.isUsingRecommendedCandidate == true)
}

@MainActor
@Test("InstallerOnboardingViewModel allows manual override while keeping recommendation")
func installerOnboardingAllowsManualOverride() {
    let small = ModelCandidate(
        id: "small",
        displayName: "Small",
        approximateDownloadSizeGB: 2.0,
        minimumMemoryGB: 8,
        tier: .small
    )
    let balanced = ModelCandidate(
        id: "balanced",
        displayName: "Balanced",
        approximateDownloadSizeGB: 5.0,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: balanced.tier.rawValue,
        candidate: balanced,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [small, balanced]
    )
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8)

    let viewModel = InstallerOnboardingViewModel(profile: profile, installerService: service)
    viewModel.selectCandidate(id: small.id)

    #expect(viewModel.selectedCandidateID == small.id)
    #expect(viewModel.selectedCandidate?.id == small.id)
    #expect(viewModel.isUsingRecommendedCandidate == false)

    viewModel.refreshRecommendation()
    #expect(viewModel.selectedCandidateID == small.id)
}

@MainActor
@Test("InstallerOnboardingViewModel completes install after successful runtime pull")
func installerOnboardingCompletesAfterRuntimePull() async throws {
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8)
    let puller = StubRuntimeModelPuller(
        events: [
            .started(modelID: candidate.id),
            .progress(completedBytes: 5, totalBytes: 10, status: "downloading"),
            .completed
        ]
    )
    let runtimeClient = StubInferenceClient()
    let installedModelStore = InMemoryInstalledModelStore()
    let actionLogStore = InMemoryInstallerActionLogStore()

    let viewModel = InstallerOnboardingViewModel(
        profile: profile,
        installerService: service,
        runtimeModelPuller: puller,
        runtimeBootstrapper: StubRuntimeBootstrapper(
            isInitiallyReachable: true,
            startIfInstalledResult: true
        ),
        runtimeClient: runtimeClient,
        installedModelStore: installedModelStore,
        actionLogStore: actionLogStore
    )

    viewModel.startInstall()
    try await eventually {
        if case .completed = viewModel.step {
            return true
        }
        return false
    }

    #expect(installedModelStore.savedRecord?.modelID == candidate.id)
    #expect(installedModelStore.savedRecord?.artifactPath == "ollama://\(candidate.id)")
    #expect(installedModelStore.savedRecord?.checksumSHA256 == "runtime-managed")
}

@MainActor
@Test("InstallerOnboardingViewModel fails install when runtime pull is unavailable")
func installerOnboardingFailsWhenRuntimePullUnavailable() async throws {
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8)
    let puller = StubRuntimeModelPuller(
        events: [],
        error: RuntimeModelPullError.unavailable("Connection refused")
    )

    let viewModel = InstallerOnboardingViewModel(
        profile: profile,
        installerService: service,
        runtimeModelPuller: puller,
        runtimeBootstrapper: StubRuntimeBootstrapper(
            isInitiallyReachable: true,
            startIfInstalledResult: true
        ),
        runtimeClient: StubInferenceClient(),
        installedModelStore: InMemoryInstalledModelStore(),
        actionLogStore: InMemoryInstallerActionLogStore()
    )

    viewModel.startInstall()
    try await eventually {
        if case .failed = viewModel.step {
            return true
        }
        return false
    }

    let errorMessage: String
    if case let .failed(message) = viewModel.step {
        errorMessage = message
    } else {
        errorMessage = ""
    }
    #expect(errorMessage.contains("Local runtime unavailable") || errorMessage.contains("Setup failed"))
}

@MainActor
@Test("InstallerOnboardingViewModel installs provider artifact and imports into runtime")
func installerOnboardingInstallsProviderArtifact() async throws {
    let providerSource = ProviderArtifactSource(
        providerName: "Test Provider",
        artifactURL: URL(string: "https://provider.example/qwen.gguf")!
    )
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced,
        installStrategy: .providerArtifact(providerSource)
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8)
    let runtimeClient = StubInferenceClient()
    let installedModelStore = InMemoryInstalledModelStore()
    let actionLogStore = InMemoryInstallerActionLogStore()
    let downloader = StubArtifactDownloader(
        events: [
            .started(resumedBytes: 0, totalBytes: 10),
            .progress(bytesWritten: 10, totalBytes: 10),
            .completed(destinationURL: URL(fileURLWithPath: "/tmp/provider.gguf"), totalBytes: 10)
        ]
    )
    let importer = StubRuntimeModelImporter(
        events: [
            .started(modelID: candidate.id),
            .status("importing"),
            .completed
        ]
    )
    let verifier = StubArtifactVerifier(checksumValue: "provider-sha256")
    let providerDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-provider-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let viewModel = InstallerOnboardingViewModel(
        profile: profile,
        installerService: service,
        runtimeModelPuller: StubRuntimeModelPuller(events: []),
        runtimeModelImporter: importer,
        artifactDownloader: downloader,
        artifactVerifier: verifier,
        runtimeBootstrapper: StubRuntimeBootstrapper(
            isInitiallyReachable: true,
            startIfInstalledResult: true
        ),
        runtimeClient: runtimeClient,
        installedModelStore: installedModelStore,
        actionLogStore: actionLogStore,
        providerArtifactsDirectoryURL: providerDirectory
    )

    viewModel.startInstall()
    try await eventually {
        if case .completed = viewModel.step {
            return true
        }
        return false
    }

    #expect(installedModelStore.savedRecord?.modelID == candidate.id)
    #expect(installedModelStore.savedRecord?.checksumSHA256 == "provider-sha256")
    #expect(installedModelStore.savedRecord?.artifactPath.contains(providerDirectory.path) == true)
}

@MainActor
@Test("InstallerOnboardingViewModel auto-installs runtime in install flow")
func installerOnboardingAutoInstallsRuntime() async throws {
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let bootstrapper = StubRuntimeBootstrapper(
        isInitiallyReachable: false,
        startIfInstalledResult: false,
        failInstallAttempts: 0
    )
    let puller = StubRuntimeModelPuller(
        events: [
            .started(modelID: candidate.id),
            .completed
        ]
    )
    let viewModel = InstallerOnboardingViewModel(
        profile: CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8),
        installerService: service,
        runtimeModelPuller: puller,
        runtimeBootstrapper: bootstrapper,
        runtimeClient: StubInferenceClient(),
        installedModelStore: InMemoryInstalledModelStore(),
        actionLogStore: InMemoryInstallerActionLogStore()
    )

    viewModel.startInstall()
    try await eventually {
        if case .completed = viewModel.step {
            return true
        }
        return false
    }

    #expect(viewModel.isRuntimeRecoveryVisible == false)
}

@MainActor
@Test("InstallerOnboardingViewModel automatic recovery action retries setup")
func installerOnboardingAutomaticRecoveryActionRetriesSetup() async throws {
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let bootstrapper = StubRuntimeBootstrapper(
        isInitiallyReachable: false,
        startIfInstalledResult: false,
        failInstallAttempts: 1
    )
    let puller = StubRuntimeModelPuller(
        events: [
            .started(modelID: candidate.id),
            .completed
        ]
    )
    let viewModel = InstallerOnboardingViewModel(
        profile: CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8),
        installerService: service,
        runtimeModelPuller: puller,
        runtimeBootstrapper: bootstrapper,
        runtimeClient: StubInferenceClient(),
        installedModelStore: InMemoryInstalledModelStore(),
        actionLogStore: InMemoryInstallerActionLogStore()
    )

    viewModel.startInstall()
    try await eventually {
        if case .failed = viewModel.step {
            return true
        }
        return false
    }

    #expect(viewModel.isRuntimeRecoveryVisible == true)

    viewModel.runAutomaticRecoveryAndRetryInstall()
    try await eventually {
        if case .completed = viewModel.step {
            return true
        }
        return false
    }
}

@MainActor
@Test("InstallerOnboardingViewModel retries transient runtime validation failures")
func installerOnboardingRetriesTransientRuntimeValidationFailures() async throws {
    let candidate = ModelCandidate(
        id: "qwen3:8b",
        displayName: "Qwen 3 8B",
        approximateDownloadSizeGB: 5.2,
        minimumMemoryGB: 16,
        tier: .balanced
    )
    let recommendation = InstallRecommendation(
        status: .ready,
        tier: candidate.tier.rawValue,
        candidate: candidate,
        rationale: "Best fit for detected hardware."
    )
    let service = StubInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let puller = StubRuntimeModelPuller(
        events: [
            .started(modelID: candidate.id),
            .completed
        ]
    )
    let runtimeClient = FlakyInferenceClient(
        transientFailureCount: 2,
        transientError: LocalRuntimeInferenceError.unavailable("The network connection was lost.")
    )

    let viewModel = InstallerOnboardingViewModel(
        profile: CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8),
        installerService: service,
        runtimeModelPuller: puller,
        runtimeBootstrapper: StubRuntimeBootstrapper(
            isInitiallyReachable: true,
            startIfInstalledResult: true
        ),
        runtimeClient: runtimeClient,
        installedModelStore: InMemoryInstalledModelStore(),
        actionLogStore: InMemoryInstallerActionLogStore()
    )

    viewModel.startInstall()
    try await eventually {
        if case .completed = viewModel.step {
            return true
        }
        return false
    }
}

private struct StubInstallerService: Installing {
    let recommendation: InstallRecommendation
    let candidates: [ModelCandidate]

    func recommendedTier() -> InstallRecommendation {
        recommendation
    }

    func recommendedInstall(for profile: CapabilityProfile) -> InstallRecommendation {
        recommendation
    }

    func compatibleCandidates(for profile: CapabilityProfile) -> [ModelCandidate] {
        candidates
    }
}

private actor StubRuntimeModelPuller: RuntimeModelPulling {
    private let events: [RuntimeModelPullEvent]
    private let error: Error?

    init(events: [RuntimeModelPullEvent], error: Error? = nil) {
        self.events = events
        self.error = error
    }

    func pullModel(_ modelID: String) async -> AsyncThrowingStream<RuntimeModelPullEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func cancelCurrentPull() async {}
}

private actor StubRuntimeModelImporter: RuntimeModelImporting {
    private let events: [RuntimeModelImportEvent]
    private let error: Error?

    init(events: [RuntimeModelImportEvent], error: Error? = nil) {
        self.events = events
        self.error = error
    }

    func importModel(modelID: String, artifactFileURL: URL) async -> AsyncThrowingStream<RuntimeModelImportEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    func cancelCurrentImport() async {}
}

private actor StubRuntimeBootstrapper: RuntimeBootstrapping {
    private var reachable: Bool
    private let startIfInstalledResult: Bool
    private let failInstallAttempts: Int
    private var installAttemptCount: Int = 0

    init(
        isInitiallyReachable: Bool,
        startIfInstalledResult: Bool,
        failInstallAttempts: Int = 0
    ) {
        self.reachable = isInitiallyReachable
        self.startIfInstalledResult = startIfInstalledResult
        self.failInstallAttempts = failInstallAttempts
    }

    func isRuntimeReachable() async -> Bool {
        reachable
    }

    func startRuntimeIfInstalled() async -> Bool {
        if startIfInstalledResult {
            reachable = true
        }
        return startIfInstalledResult
    }

    func installAndStartRuntime() async throws {
        installAttemptCount += 1
        if installAttemptCount <= failInstallAttempts {
            throw RuntimeBootstrapError.runtimeUnavailableAfterStart
        }
        reachable = true
    }
}

private final class StubArtifactDownloader: ArtifactDownloading {
    private let events: [ArtifactDownloadEvent]

    init(events: [ArtifactDownloadEvent]) {
        self.events = events
    }

    func startDownload(_ request: ArtifactDownloadRequest) -> AsyncThrowingStream<ArtifactDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func cancelDownload(id: String) {}
}

private struct StubArtifactVerifier: ArtifactVerifying {
    let checksumValue: String

    func checksum(for fileURL: URL, algorithm: ArtifactHashAlgorithm) throws -> String {
        checksumValue
    }

    func verify(fileURL: URL, against checksum: ArtifactChecksum) throws {}
}

private actor StubInferenceClient: InferenceClient {
    func loadModel(_ model: InferenceModelDescriptor) async throws {}

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRequest() async {}
}

private actor FlakyInferenceClient: InferenceClient {
    private var remainingFailures: Int
    private let transientError: Error

    init(transientFailureCount: Int, transientError: Error) {
        remainingFailures = transientFailureCount
        self.transientError = transientError
    }

    func loadModel(_ model: InferenceModelDescriptor) async throws {
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw transientError
        }
    }

    func streamCompletion(_ request: InferenceRequest) async -> AsyncThrowingStream<InferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func cancelCurrentRequest() async {}
}

private final class InMemoryInstalledModelStore: InstalledModelStoring {
    private(set) var savedRecord: InstalledModelRecord?

    func save(record: InstalledModelRecord) throws {
        savedRecord = record
    }

    func load() throws -> InstalledModelRecord {
        guard let savedRecord else {
            throw InstalledModelStoreError.notFound
        }
        return savedRecord
    }

    func loadIfAvailable() throws -> InstalledModelRecord? {
        savedRecord
    }

    func clear() throws {
        savedRecord = nil
    }
}

private final class InMemoryInstallerActionLogStore: @unchecked Sendable, InstallerActionLogging {
    private var entries: [InstallerActionLogEntry] = []

    func append(_ entry: InstallerActionLogEntry) throws {
        entries.append(entry)
    }

    func listEntries(limit: Int?) throws -> [InstallerActionLogEntry] {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
        guard let limit, limit >= 0 else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func exportText(limit: Int?) throws -> String {
        let listed = try listEntries(limit: limit)
        return listed.map(\.message).joined(separator: "\n")
    }
}

@MainActor
private func eventually(
    timeout: Duration = .seconds(2),
    condition: @MainActor @escaping () -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    throw PollingTimeoutError()
}

private struct PollingTimeoutError: Error {}
#endif
