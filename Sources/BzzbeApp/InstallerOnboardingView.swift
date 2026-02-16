#if canImport(SwiftUI)
import CoreHardware
import CoreInference
import CoreInstaller
import Foundation
import SwiftUI

@MainActor
final class InstallerOnboardingViewModel: ObservableObject {
    enum Step: Equatable {
        case intro
        case recommendation
        case installing
        case failed(message: String)
        case completed
    }

    @Published private(set) var step: Step = .intro
    @Published private(set) var recommendation: InstallRecommendation
    @Published private(set) var availableCandidates: [ModelCandidate]
    @Published private(set) var recommendedCandidateID: String?
    @Published private(set) var selectedCandidateID: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "Ready to start setup."
    @Published private(set) var isInstalling: Bool = false

    let profile: CapabilityProfile

    var selectedCandidate: ModelCandidate? {
        guard let selectedCandidateID else { return nil }
        return availableCandidates.first(where: { $0.id == selectedCandidateID })
    }

    var isUsingRecommendedCandidate: Bool {
        selectedCandidateID == recommendedCandidateID
    }

    private let installerService: Installing
    private let runtimeModelPuller: RuntimeModelPulling
    private let runtimeModelImporter: RuntimeModelImporting
    private let artifactDownloader: ArtifactDownloading
    private let artifactVerifier: ArtifactVerifying
    private let runtimeClient: any InferenceClient
    private let installedModelStore: InstalledModelStoring
    private let actionLogStore: InstallerActionLogging
    private let fileManager: FileManager
    private let providerArtifactsDirectoryURL: URL
    private var installTask: Task<Void, Never>?
    private var activeProviderDownloadID: String?

    init(
        profile: CapabilityProfile,
        installerService: Installing = InstallerService(),
        runtimeModelPuller: RuntimeModelPulling = OllamaModelPullClient(),
        runtimeModelImporter: RuntimeModelImporting = OllamaModelImportClient(),
        artifactDownloader: ArtifactDownloading = ResumableArtifactDownloadManager(),
        artifactVerifier: ArtifactVerifying = ArtifactVerifier(),
        runtimeClient: any InferenceClient = LocalRuntimeInferenceClient(),
        installedModelStore: InstalledModelStoring = JSONInstalledModelStore.defaultStore(),
        actionLogStore: InstallerActionLogging = JSONInstallerActionLogStore.defaultStore(),
        fileManager: FileManager = .default,
        providerArtifactsDirectoryURL: URL = InstallerOnboardingViewModel.defaultProviderArtifactsDirectoryURL()
    ) {
        self.profile = profile
        self.installerService = installerService
        self.runtimeModelPuller = runtimeModelPuller
        self.runtimeModelImporter = runtimeModelImporter
        self.artifactDownloader = artifactDownloader
        self.artifactVerifier = artifactVerifier
        self.runtimeClient = runtimeClient
        self.installedModelStore = installedModelStore
        self.actionLogStore = actionLogStore
        self.fileManager = fileManager
        self.providerArtifactsDirectoryURL = providerArtifactsDirectoryURL
        let recommendation = installerService.recommendedInstall(for: profile)
        self.recommendation = recommendation
        let availableCandidates = installerService.compatibleCandidates(for: profile)
        self.availableCandidates = availableCandidates
        self.recommendedCandidateID = recommendation.candidate?.id
        self.selectedCandidateID = recommendation.candidate?.id ?? availableCandidates.first?.id
    }

    deinit {
        installTask?.cancel()
    }

    func continueFromIntro() {
        step = .recommendation
    }

    func refreshRecommendation() {
        recommendation = installerService.recommendedInstall(for: profile)
        availableCandidates = installerService.compatibleCandidates(for: profile)
        recommendedCandidateID = recommendation.candidate?.id

        if let selectedCandidateID,
           availableCandidates.contains(where: { $0.id == selectedCandidateID }) {
            self.selectedCandidateID = selectedCandidateID
        } else {
            self.selectedCandidateID = recommendation.candidate?.id ?? availableCandidates.first?.id
        }

        step = .recommendation
    }

    func selectCandidate(id: String) {
        guard availableCandidates.contains(where: { $0.id == id }) else { return }
        selectedCandidateID = id
    }

    func startInstall() {
        guard recommendation.status == .ready, let candidate = selectedCandidate else {
            logAction(
                category: "install.blocked",
                message: "Install blocked due to insufficient resources: \(insufficientResourcesMessage())"
            )
            step = .failed(message: insufficientResourcesMessage())
            return
        }

        installTask?.cancel()
        installTask = Task { [weak self] in
            await self?.performInstallFlow(candidate: candidate)
        }
    }

    func cancelInstall() {
        guard isInstalling else { return }
        statusText = "Cancelling setup..."
        installTask?.cancel()
        installTask = nil

        if let activeProviderDownloadID {
            artifactDownloader.cancelDownload(id: activeProviderDownloadID)
            self.activeProviderDownloadID = nil
        }

        Task {
            await runtimeModelPuller.cancelCurrentPull()
            await runtimeModelImporter.cancelCurrentImport()
        }
    }

    func retryInstall() {
        startInstall()
    }

    private func performInstallFlow(candidate: ModelCandidate) async {
        progress = 0
        isInstalling = true
        step = .installing
        statusText = "Preparing setup..."

        do {
            logAction(
                category: "install.started",
                message: "Starting install for \(candidate.id) (\(candidate.tier.rawValue))."
            )
            let installedArtifactMetadata = try await installCandidateArtifact(candidate)

            statusText = "Verifying local runtime and model availability..."
            logAction(
                category: "runtime.validation.started",
                message: "Checking runtime/model availability for \(candidate.id)."
            )
            try await ensureRuntimeModelAvailable(for: candidate)
            logAction(
                category: "runtime.validation.passed",
                message: "Runtime confirmed model availability for \(candidate.id)."
            )

            try persistInstalledModelMetadata(
                for: candidate,
                artifactPath: installedArtifactMetadata.artifactPath,
                checksumSHA256: installedArtifactMetadata.checksumSHA256
            )
            logAction(
                category: "model.persisted",
                message: "Persisted installed model metadata for \(candidate.id)."
            )
            statusText = "Setup complete."
            isInstalling = false
            step = .completed
            installTask = nil
            logAction(
                category: "install.completed",
                message: "Install completed for \(candidate.id)."
            )
        } catch is CancellationError {
            isInstalling = false
            step = .failed(message: "Setup was cancelled. You can retry safely.")
            statusText = "Setup cancelled."
            installTask = nil
            activeProviderDownloadID = nil
            logAction(category: "install.cancelled", message: "Install was cancelled by the user.")
        } catch {
            isInstalling = false
            step = .failed(message: "Setup failed: \(error.localizedDescription)")
            statusText = "Setup failed."
            installTask = nil
            activeProviderDownloadID = nil
            logAction(category: "install.failed", message: error.localizedDescription)
        }
    }

    private struct InstalledArtifactMetadata {
        let artifactPath: String
        let checksumSHA256: String
    }

    private func installCandidateArtifact(_ candidate: ModelCandidate) async throws -> InstalledArtifactMetadata {
        switch candidate.installStrategy {
        case .runtimeRegistryPull:
            try await installViaRuntimeRegistryPull(candidate)
            return InstalledArtifactMetadata(
                artifactPath: "ollama://\(candidate.id)",
                checksumSHA256: "runtime-managed"
            )
        case let .providerArtifact(source):
            return try await installViaProviderArtifact(candidate: candidate, source: source)
        }
    }

    private func installViaRuntimeRegistryPull(_ candidate: ModelCandidate) async throws {
        var completed = false
        var didLogPullStart = false

        let stream = await runtimeModelPuller.pullModel(candidate.id)
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .started:
                progress = 0
                statusText = "Starting model download..."
                if !didLogPullStart {
                    didLogPullStart = true
                    logAction(
                        category: "runtime.pull.started",
                        message: "Started runtime model pull for \(candidate.id)."
                    )
                }
            case let .status(message):
                statusText = message
            case let .progress(completedBytes, totalBytes, status):
                progress = fraction(numerator: completedBytes, denominator: totalBytes)
                if let status, !status.isEmpty {
                    statusText = status
                } else {
                    statusText = "Downloading model package..."
                }
            case .completed:
                progress = 1
                statusText = "Model download complete. Verifying runtime..."
                logAction(
                    category: "runtime.pull.completed",
                    message: "Runtime reported model pull complete for \(candidate.id)."
                )
                completed = true
            }
        }

        if !completed {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw InstallationFlowError.downloadEndedUnexpectedly
        }
    }

    private func installViaProviderArtifact(
        candidate: ModelCandidate,
        source: ProviderArtifactSource
    ) async throws -> InstalledArtifactMetadata {
        let artifactFileURL = try destinationArtifactFileURL(for: candidate, source: source)
        let downloadRequestID = "provider.\(candidate.id)"
        activeProviderDownloadID = downloadRequestID

        logAction(
            category: "provider.download.started",
            message: "Downloading \(candidate.id) from \(source.providerName)."
        )

        let request = ArtifactDownloadRequest(
            id: downloadRequestID,
            sourceURL: source.artifactURL,
            destinationURL: artifactFileURL
        )
        let stream = artifactDownloader.startDownload(request)
        var didCompleteDownload = false

        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case let .started(resumedBytes, totalBytes):
                progress = fraction(numerator: resumedBytes, denominator: totalBytes)
                if resumedBytes > 0 {
                    statusText = "Resuming provider download..."
                } else {
                    statusText = "Downloading model from provider..."
                }
            case let .progress(bytesWritten, totalBytes):
                progress = fraction(numerator: bytesWritten, denominator: totalBytes)
                statusText = "Downloading model from provider..."
            case .completed:
                progress = 1
                statusText = "Provider download complete."
                didCompleteDownload = true
            }
        }
        activeProviderDownloadID = nil

        if !didCompleteDownload {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw InstallationFlowError.downloadEndedUnexpectedly
        }

        logAction(
            category: "provider.download.completed",
            message: "Downloaded provider artifact for \(candidate.id) to \(artifactFileURL.path)."
        )

        let computedChecksum = try artifactVerifier.checksum(for: artifactFileURL, algorithm: .sha256)
        if let expectedChecksum = source.checksumSHA256 {
            let expected = try ArtifactChecksum(value: expectedChecksum)
            try artifactVerifier.verify(fileURL: artifactFileURL, against: expected)
            logAction(
                category: "provider.verify.passed",
                message: "Checksum verified for \(candidate.id)."
            )
        } else {
            logAction(
                category: "provider.verify.skipped",
                message: "No checksum configured for \(candidate.id); recorded computed SHA-256."
            )
        }

        statusText = "Registering downloaded model in local runtime..."
        let importStream = await runtimeModelImporter.importModel(
            modelID: candidate.id,
            artifactFileURL: artifactFileURL
        )
        var importCompleted = false
        for try await event in importStream {
            try Task.checkCancellation()
            switch event {
            case .started:
                statusText = "Importing downloaded model..."
                logAction(
                    category: "runtime.import.started",
                    message: "Started runtime import for \(candidate.id)."
                )
            case let .status(message):
                statusText = message
            case .completed:
                importCompleted = true
            }
        }

        if !importCompleted {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw InstallationFlowError.importEndedUnexpectedly
        }

        logAction(
            category: "runtime.import.completed",
            message: "Runtime import completed for \(candidate.id)."
        )

        return InstalledArtifactMetadata(
            artifactPath: artifactFileURL.path,
            checksumSHA256: computedChecksum
        )
    }

    private func ensureRuntimeModelAvailable(for candidate: ModelCandidate) async throws {
        let model = InferenceModelDescriptor(
            identifier: candidate.id,
            displayName: candidate.displayName,
            contextWindow: 32_768
        )

        do {
            try await runtimeClient.loadModel(model)
        } catch let error as LocalRuntimeInferenceError {
            switch error {
            case .unavailable:
                throw InstallationFlowError.runtimeUnavailable(
                    "Local runtime is not reachable at http://127.0.0.1:11434. Install and start Ollama, then retry setup."
                )
            case let .runtime(details):
                if isMissingModelError(details) {
                    throw InstallationFlowError.modelMissing(
                        "Local runtime did not report model '\(candidate.id)' as installed after setup. Retry setup."
                    )
                }
                throw InstallationFlowError.runtimeUnavailable(error.localizedDescription)
            case .invalidResponseStatus, .invalidResponse:
                throw InstallationFlowError.runtimeUnavailable(error.localizedDescription)
            }
        } catch {
            throw InstallationFlowError.runtimeUnavailable(error.localizedDescription)
        }
    }

    private func isMissingModelError(_ details: String) -> Bool {
        let normalized = details.lowercased()
        return normalized.contains("not found")
            || normalized.contains("no such model")
            || normalized.contains("unknown model")
    }

    private func persistInstalledModelMetadata(
        for candidate: ModelCandidate,
        artifactPath: String,
        checksumSHA256: String
    ) throws {
        let record = InstalledModelRecord(
            modelID: candidate.id,
            tier: candidate.tier.rawValue,
            artifactPath: artifactPath,
            checksumSHA256: checksumSHA256,
            version: "1"
        )
        try installedModelStore.save(record: record)
    }

    private func destinationArtifactFileURL(
        for candidate: ModelCandidate,
        source: ProviderArtifactSource
    ) throws -> URL {
        try fileManager.createDirectory(at: providerArtifactsDirectoryURL, withIntermediateDirectories: true)

        let fileName: String
        let sourceFileName = source.artifactURL.lastPathComponent
        if sourceFileName.isEmpty {
            fileName = sanitizedFileName(candidate.id) + ".gguf"
        } else {
            fileName = sanitizedFileName(sourceFileName)
        }

        return providerArtifactsDirectoryURL
            .appendingPathComponent(candidate.id.replacingOccurrences(of: ":", with: "-"), isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private func sanitizedFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let mappedScalars = value.unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            return "-"
        }
        let candidate = mappedScalars.joined()
        if candidate.isEmpty {
            return "artifact.gguf"
        }
        return candidate
    }

    private static func defaultProviderArtifactsDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Bzzbe", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("provider-artifacts", isDirectory: true)
    }

    private func fraction(numerator: Int64, denominator: Int64) -> Double {
        guard denominator > 0 else { return 0 }
        return min(1, max(0, Double(numerator) / Double(denominator)))
    }

    private func insufficientResourcesMessage() -> String {
        let memory = recommendation.minimumRequiredMemoryGB.map { "\($0)GB RAM" } ?? "unknown RAM"
        let disk = recommendation.minimumRequiredDiskGB.map { "\($0)GB free disk" } ?? "unknown disk space"
        return "This Mac currently does not meet minimum requirements (\(memory), \(disk))."
    }

    private func logAction(category: String, message: String) {
        let entry = InstallerActionLogEntry(category: category, message: message)
        try? actionLogStore.append(entry)
    }
}

private enum InstallationFlowError: Error {
    case runtimeUnavailable(String)
    case modelMissing(String)
    case downloadEndedUnexpectedly
    case importEndedUnexpectedly
}

extension InstallationFlowError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(message):
            return message
        case let .modelMissing(message):
            return message
        case .downloadEndedUnexpectedly:
            return "Model pull ended unexpectedly before completion."
        case .importEndedUnexpectedly:
            return "Model import ended unexpectedly before completion."
        }
    }
}

struct InstallerOnboardingView: View {
    @StateObject private var viewModel: InstallerOnboardingViewModel
    let onComplete: () -> Void

    init(
        profile: CapabilityProfile,
        installerService: Installing = InstallerService(),
        onComplete: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: InstallerOnboardingViewModel(profile: profile, installerService: installerService)
        )
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            content
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to Bzzbe")
                .font(.largeTitle.bold())
            Text("Set up your local AI runtime in a few guided steps.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Detected hardware: \(viewModel.profile.memoryGB)GB RAM, \(viewModel.profile.freeDiskGB)GB free disk")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .intro:
            introStep
        case .recommendation:
            recommendationStep
        case .installing:
            installingStep
        case let .failed(message):
            failureStep(message: message)
        case .completed:
            completedStep
        }
    }

    private var introStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Before you start")
                .font(.headline)
            Text("Bzzbe runs models on-device by default. Setup will configure a local runtime and install a recommended model profile for this Mac.")
                .foregroundStyle(.secondary)
            Text("Model download is handled in-app. If the local runtime is unavailable, setup will show how to fix it and retry.")
                .font(.subheadline.weight(.semibold))
            Button("Continue") {
                viewModel.continueFromIntro()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var recommendationStep: some View {
        switch viewModel.recommendation.status {
        case .ready:
            VStack(alignment: .leading, spacing: 14) {
                if let candidate = viewModel.recommendation.candidate {
                    GroupBox("Recommended Profile") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(candidate.displayName)
                                .font(.headline)
                            Text("Tier: \(viewModel.recommendation.tier ?? "unknown")")
                            Text("Approximate download: \(candidate.approximateDownloadSizeGB, specifier: "%.1f")GB")
                            Text("Minimum memory: \(candidate.minimumMemoryGB)GB")
                            Text("Install source: \(installSourceSummary(candidate))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(viewModel.recommendation.rationale)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !viewModel.availableCandidates.isEmpty {
                    GroupBox("Model Selection") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default selection is based on your hardware. You can override it.")
                                .foregroundStyle(.secondary)
                            Picker(
                                "Model",
                                selection: Binding(
                                    get: { viewModel.selectedCandidateID ?? "" },
                                    set: { viewModel.selectCandidate(id: $0) }
                                )
                            ) {
                                ForEach(viewModel.availableCandidates, id: \.id) { candidate in
                                    Text(candidateMenuLabel(for: candidate))
                                        .tag(candidate.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let selectedCandidate = viewModel.selectedCandidate {
                    GroupBox(viewModel.isUsingRecommendedCandidate ? "Selected Model (Recommended)" : "Selected Model (Override)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selectedCandidate.displayName)
                                .font(.headline)
                            Text("Tier: \(selectedCandidate.tier.rawValue)")
                            Text("Approximate download: \(selectedCandidate.approximateDownloadSizeGB, specifier: "%.1f")GB")
                            Text("Minimum memory: \(selectedCandidate.minimumMemoryGB)GB")
                            Text("Install source: \(installSourceSummary(selectedCandidate))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if !viewModel.isUsingRecommendedCandidate,
                               let recommended = viewModel.recommendation.candidate {
                                Text("Override active. Hardware recommendation is \(recommended.displayName).")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack(spacing: 10) {
                    Button("Install") {
                        viewModel.startInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.selectedCandidate == nil)

                    Button("Re-check Hardware") {
                        viewModel.refreshRecommendation()
                    }
                    .buttonStyle(.bordered)
                }
            }
        case .insufficientResources:
            failureStep(message: viewModel.recommendation.rationale)
        }
    }

    private func candidateMenuLabel(for candidate: ModelCandidate) -> String {
        if candidate.id == viewModel.recommendedCandidateID {
            return "\(candidate.displayName) (Recommended)"
        }
        return candidate.displayName
    }

    private func installSourceSummary(_ candidate: ModelCandidate) -> String {
        switch candidate.installStrategy {
        case .runtimeRegistryPull:
            return "Runtime registry pull"
        case let .providerArtifact(source):
            return "Provider download (\(source.providerName))"
        }
    }

    private var installingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installing")
                .font(.headline)
            ProgressView(value: viewModel.progress)
                .frame(maxWidth: 460)
            Text(viewModel.statusText)
                .foregroundStyle(.secondary)
            Text("\(Int((viewModel.progress * 100).rounded()))%")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                viewModel.cancelInstall()
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.isInstalling)
        }
    }

    private func failureStep(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Needs Attention")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Retry") {
                    viewModel.retryInstall()
                }
                .buttonStyle(.borderedProminent)

                Button("Back") {
                    viewModel.refreshRecommendation()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var completedStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Complete")
                .font(.headline)
            Text("Bzzbe is ready. You can now open chat, tasks, models, and settings.")
                .foregroundStyle(.secondary)

            Button("Open Bzzbe") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
#endif
