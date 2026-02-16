import CoreHardware
import CoreInstaller
import Testing

@Test("InstallerService chooses high_quality tier for 24GB machines")
func recommendsHighQualityOn24GB() {
    let service = InstallerService()
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 24, freeDiskGB: 128, performanceCores: 10)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.tier == "high_quality")
    #expect(recommendation.candidate.minimumMemoryGB <= profile.memoryGB)
}

@Test("InstallerService falls back to small tier on constrained machines")
func recommendsSmallWhenResourcesConstrained() {
    let service = InstallerService()
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 8, freeDiskGB: 20, performanceCores: 8)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(recommendation.tier == "small")
    #expect(!recommendation.candidate.id.isEmpty)
}

@Test("InstallerService ignores empty custom catalogs and uses defaults")
func ignoresEmptyCatalog() {
    let service = InstallerService(catalog: [])
    let profile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 64, performanceCores: 8)

    let recommendation = service.recommendedInstall(for: profile)

    #expect(!recommendation.candidate.id.isEmpty)
    #expect(InstallerService.defaultCatalog.contains(where: { $0.id == recommendation.candidate.id }))
}
