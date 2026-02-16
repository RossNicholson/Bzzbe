#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreHardware
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
#endif
