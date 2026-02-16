#if canImport(SwiftUI)
import CoreHardware
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
    private let artifactDownloader: ArtifactDownloading
    private let artifactVerifier: ArtifactVerifying
    private let installedModelStore: InstalledModelStoring
    private let actionLogStore: InstallerActionLogging
    private let fileManager: FileManager
    private var installTask: Task<Void, Never>?
    private var activeDownloadID: String?

    init(
        profile: CapabilityProfile,
        installerService: Installing = InstallerService(),
        artifactDownloader: ArtifactDownloading = ResumableArtifactDownloadManager(),
        artifactVerifier: ArtifactVerifying = ArtifactVerifier(),
        installedModelStore: InstalledModelStoring = JSONInstalledModelStore.defaultStore(),
        actionLogStore: InstallerActionLogging = JSONInstallerActionLogStore.defaultStore(),
        fileManager: FileManager = .default
    ) {
        self.profile = profile
        self.installerService = installerService
        self.artifactDownloader = artifactDownloader
        self.artifactVerifier = artifactVerifier
        self.installedModelStore = installedModelStore
        self.actionLogStore = actionLogStore
        self.fileManager = fileManager
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
        if let activeDownloadID {
            artifactDownloader.cancelDownload(id: activeDownloadID)
        }
        installTask?.cancel()
        installTask = nil
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
            let plan = try makeDownloadPlan(for: candidate)
            logAction(
                category: "install.started",
                message: "Starting install for \(plan.candidate.id) (\(plan.tier))."
            )
            activeDownloadID = plan.request.id
            var completed = false
            var didLogDownloadStart = false

            let stream = artifactDownloader.startDownload(plan.request)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case let .started(resumedBytes, totalBytes):
                    progress = fraction(numerator: resumedBytes, denominator: totalBytes)
                    if !didLogDownloadStart {
                        didLogDownloadStart = true
                        if resumedBytes > 0 {
                            logAction(
                                category: "download.resumed",
                                message: "Resumed \(plan.request.id) at \(resumedBytes) of \(totalBytes) bytes."
                            )
                        } else {
                            logAction(
                                category: "download.started",
                                message: "Started \(plan.request.id) with expected size \(totalBytes) bytes."
                            )
                        }
                    }
                    if resumedBytes > 0 {
                        statusText = "Resuming download (\(resumedBytes / 1024)KB already downloaded)"
                    } else {
                        statusText = "Starting download..."
                    }
                case let .progress(bytesWritten, totalBytes):
                    progress = fraction(numerator: bytesWritten, denominator: totalBytes)
                    statusText = "Downloading model package..."
                case .completed:
                    progress = 1
                    statusText = "Download complete. Verifying artifact..."
                    logAction(
                        category: "download.completed",
                        message: "Completed \(plan.request.id). Starting verification."
                    )
                    completed = true
                }
            }

            if completed {
                do {
                    try artifactVerifier.verify(fileURL: plan.request.destinationURL, against: plan.expectedChecksum)
                    logAction(
                        category: "verification.passed",
                        message: "Checksum passed for \(plan.request.destinationURL.lastPathComponent)."
                    )
                } catch {
                    logAction(
                        category: "verification.failed",
                        message: error.localizedDescription
                    )
                    try? fileManager.removeItem(at: plan.request.destinationURL)
                    throw error
                }

                try persistInstalledModelMetadata(plan)
                logAction(
                    category: "model.persisted",
                    message: "Persisted installed model metadata for \(plan.candidate.id)."
                )
                statusText = "Verification passed. Setup complete."
                isInstalling = false
                step = .completed
                installTask = nil
                activeDownloadID = nil
                logAction(
                    category: "install.completed",
                    message: "Install completed for \(plan.candidate.id)."
                )
            } else if Task.isCancelled {
                throw CancellationError()
            } else {
                throw InstallationFlowError.downloadEndedUnexpectedly
            }
        } catch is CancellationError {
            isInstalling = false
            step = .failed(message: "Setup was cancelled. You can retry safely.")
            statusText = "Setup cancelled."
            installTask = nil
            activeDownloadID = nil
            logAction(category: "install.cancelled", message: "Install was cancelled by the user.")
        } catch {
            isInstalling = false
            step = .failed(message: "Setup failed: \(error.localizedDescription)")
            statusText = "Setup failed."
            installTask = nil
            activeDownloadID = nil
            logAction(category: "install.failed", message: error.localizedDescription)
        }
    }

    private struct DownloadPlan {
        let candidate: ModelCandidate
        let tier: String
        let request: ArtifactDownloadRequest
        let expectedChecksum: ArtifactChecksum
    }

    private func makeDownloadPlan(for candidate: ModelCandidate) throws -> DownloadPlan {
        let root = try installerWorkspaceRoot()
        let sourceDirectory = root.appendingPathComponent("seed-artifacts", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent("downloads", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let safeIdentifier = sanitizedIdentifier(candidate.id)
        let seedURL = sourceDirectory.appendingPathComponent("\(safeIdentifier).seed", isDirectory: false)
        let destinationURL = destinationDirectory.appendingPathComponent("\(safeIdentifier).artifact", isDirectory: false)

        try ensureSeedArtifactExists(at: seedURL, approximateSizeGB: candidate.approximateDownloadSizeGB)
        let expectedSHA256 = try artifactVerifier.checksum(for: seedURL, algorithm: .sha256)
        let expectedChecksum = try ArtifactChecksum(value: expectedSHA256)

        return DownloadPlan(
            candidate: candidate,
            tier: candidate.tier.rawValue,
            request: ArtifactDownloadRequest(
                id: "installer.\(safeIdentifier)",
                sourceURL: seedURL,
                destinationURL: destinationURL
            ),
            expectedChecksum: expectedChecksum
        )
    }

    private func persistInstalledModelMetadata(_ plan: DownloadPlan) throws {
        let record = InstalledModelRecord(
            modelID: plan.candidate.id,
            tier: plan.tier,
            artifactPath: plan.request.destinationURL.path,
            checksumSHA256: plan.expectedChecksum.value,
            version: "1"
        )
        try installedModelStore.save(record: record)
    }

    private func installerWorkspaceRoot() throws -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let root = base.appendingPathComponent("Bzzbe", isDirectory: true)
            .appendingPathComponent("installer", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func ensureSeedArtifactExists(at url: URL, approximateSizeGB: Double) throws {
        let byteCount = targetSeedArtifactBytes(approximateSizeGB: approximateSizeGB)

        if fileManager.fileExists(atPath: url.path),
           let existingSize = try? fileSize(at: url),
           existingSize == byteCount {
            return
        }

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        fileManager.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        var remaining = byteCount
        let chunk = Data(repeating: 0x42, count: 64 * 1024)
        while remaining > 0 {
            let sliceCount = min(chunk.count, remaining)
            try handle.write(contentsOf: chunk.prefix(sliceCount))
            remaining -= sliceCount
        }
    }

    private func targetSeedArtifactBytes(approximateSizeGB: Double) -> Int {
        let baseline = Int(max(1.0, approximateSizeGB) * 350_000)
        return max(512 * 1024, min(4 * 1024 * 1024, baseline))
    }

    private func fileSize(at url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return values.fileSize ?? 0
    }

    private func sanitizedIdentifier(_ value: String) -> String {
        let sanitized = value.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]"#,
            with: "_",
            options: .regularExpression
        )
        return sanitized.isEmpty ? "artifact" : sanitized
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
    case downloadEndedUnexpectedly
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
            Text("No Terminal commands are required.")
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
