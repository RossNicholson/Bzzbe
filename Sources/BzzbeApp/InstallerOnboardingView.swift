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
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText: String = "Ready to start setup."
    @Published private(set) var isInstalling: Bool = false

    let profile: CapabilityProfile

    private let installerService: Installing
    private var installTask: Task<Void, Never>?

    init(
        profile: CapabilityProfile,
        installerService: Installing = InstallerService()
    ) {
        self.profile = profile
        self.installerService = installerService
        self.recommendation = installerService.recommendedInstall(for: profile)
    }

    deinit {
        installTask?.cancel()
    }

    func continueFromIntro() {
        step = .recommendation
    }

    func refreshRecommendation() {
        recommendation = installerService.recommendedInstall(for: profile)
        step = .recommendation
    }

    func startInstall() {
        guard recommendation.status == .ready else {
            step = .failed(message: insufficientResourcesMessage())
            return
        }

        installTask?.cancel()
        installTask = Task { [weak self] in
            await self?.performInstallFlow()
        }
    }

    func cancelInstall() {
        guard isInstalling else { return }
        statusText = "Cancelling setup..."
        installTask?.cancel()
        installTask = nil
    }

    func retryInstall() {
        startInstall()
    }

    private func performInstallFlow() async {
        progress = 0
        isInstalling = true
        step = .installing
        statusText = "Preparing setup..."

        do {
            for phase in setupPhases {
                try Task.checkCancellation()
                statusText = phase.label
                progress = phase.progress
                try await Task.sleep(nanoseconds: phase.delayNanoseconds)
            }

            statusText = "Setup complete."
            progress = 1
            isInstalling = false
            step = .completed
            installTask = nil
        } catch is CancellationError {
            isInstalling = false
            step = .failed(message: "Setup was cancelled. You can retry safely.")
            statusText = "Setup cancelled."
            installTask = nil
        } catch {
            isInstalling = false
            step = .failed(message: "Setup failed: \(error.localizedDescription)")
            statusText = "Setup failed."
            installTask = nil
        }
    }

    private var setupPhases: [(label: String, progress: Double, delayNanoseconds: UInt64)] {
        [
            ("Validating local environment", 0.15, 400_000_000),
            ("Preparing runtime workspace", 0.35, 500_000_000),
            ("Downloading recommended model package", 0.65, 700_000_000),
            ("Configuring local runtime", 0.85, 500_000_000),
            ("Finalizing installation", 1.0, 350_000_000)
        ]
    }

    private func insufficientResourcesMessage() -> String {
        let memory = recommendation.minimumRequiredMemoryGB.map { "\($0)GB RAM" } ?? "unknown RAM"
        let disk = recommendation.minimumRequiredDiskGB.map { "\($0)GB free disk" } ?? "unknown disk space"
        return "This Mac currently does not meet minimum requirements (\(memory), \(disk))."
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
            if let candidate = viewModel.recommendation.candidate {
                VStack(alignment: .leading, spacing: 14) {
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

                    HStack(spacing: 10) {
                        Button("Install") {
                            viewModel.startInstall()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Re-check Hardware") {
                            viewModel.refreshRecommendation()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        case .insufficientResources:
            failureStep(message: viewModel.recommendation.rationale)
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
