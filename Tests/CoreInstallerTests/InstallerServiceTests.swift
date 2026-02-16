import CoreHardware
import CoreInstaller
import Testing

@Test("InstallerService chooses high_quality tier for 24GB machines")
func recommendsHighQualityOn24GB() {
    let service = InstallerService()
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 24, freeDiskGB: 128, performanceCores: 10)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.status == .ready)
    #expect(recommendation.tier == "high_quality")
    #expect((recommendation.candidate?.minimumMemoryGB ?? .max) <= profile.memoryGB)
}

@Test("InstallerService falls back to small tier on constrained machines")
func recommendsSmallWhenResourcesConstrained() {
    let service = InstallerService()
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 8, freeDiskGB: 20, performanceCores: 8)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.status == .ready)
    #expect(recommendation.tier == "small")
    #expect(!(recommendation.candidate?.id.isEmpty ?? true))
}

@Test("InstallerService ignores empty custom catalogs and uses defaults")
func ignoresEmptyCatalog() {
    let service = InstallerService(catalog: [])
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 64, performanceCores: 8)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.status == .ready)
    #expect(!(recommendation.candidate?.id.isEmpty ?? true))
    #expect(InstallerService.defaultCatalog.contains(where: { $0.id == recommendation.candidate?.id }))
}

@Test("InstallerService returns insufficientResources when no model fits")
func returnsInsufficientResourcesWhenNoModelFits() {
    let service = InstallerService()
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 4, freeDiskGB: 1, performanceCores: 4)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.status == .insufficientResources)
    #expect(recommendation.tier == nil)
    #expect(recommendation.candidate == nil)
    #expect((recommendation.minimumRequiredMemoryGB ?? 0) >= 8)
    #expect((recommendation.minimumRequiredDiskGB ?? 0) >= 4)
}

@Test("InstallerService exposes compatible candidates for manual override choices")
func returnsCompatibleCandidatesForProfile() {
    let service = InstallerService(catalog: [
        .init(id: "small", displayName: "Small", approximateDownloadSizeGB: 2.0, minimumMemoryGB: 8, tier: .small),
        .init(id: "balanced", displayName: "Balanced", approximateDownloadSizeGB: 5.0, minimumMemoryGB: 16, tier: .balanced),
        .init(id: "high", displayName: "High", approximateDownloadSizeGB: 9.0, minimumMemoryGB: 24, tier: .highQuality)
    ])
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 11, performanceCores: 8)

    let candidates = service.compatibleCandidates(for: profile)

    #expect(candidates.map(\.id) == ["small", "balanced"])
}
