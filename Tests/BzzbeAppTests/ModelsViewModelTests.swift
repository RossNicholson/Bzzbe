#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreHardware
import CoreInstaller
import Foundation
import Testing

@MainActor
@Test("ModelsViewModel loads recommendation and installed metadata")
func modelsViewModelLoadsRecommendationAndMetadata() {
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
        rationale: "Best fit."
    )
    let service = StubModelInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let store = InMemorySingleInstalledModelStore(
        record: InstalledModelRecord(
            modelID: candidate.id,
            tier: candidate.tier.rawValue,
            artifactPath: "ollama://\(candidate.id)",
            checksumSHA256: "runtime-managed",
            version: "1"
        )
    )
    let viewModel = ModelsViewModel(
        profile: CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8),
        installerService: service,
        installedModelStore: store,
        actionLogStore: InMemoryModelsActionLogStore()
    )

    #expect(viewModel.recommendation.candidate?.id == candidate.id)
    #expect(viewModel.compatibleCandidates.map(\.id) == [candidate.id])
    #expect(viewModel.installedRecord?.modelID == candidate.id)
}

@MainActor
@Test("ModelsViewModel clear removes installed metadata and logs action")
func modelsViewModelClearMetadata() {
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
        rationale: "Best fit."
    )
    let service = StubModelInstallerService(
        recommendation: recommendation,
        candidates: [candidate]
    )
    let store = InMemorySingleInstalledModelStore(
        record: InstalledModelRecord(
            modelID: candidate.id,
            tier: candidate.tier.rawValue,
            artifactPath: "ollama://\(candidate.id)",
            checksumSHA256: "runtime-managed",
            version: "1"
        )
    )
    let actionLog = InMemoryModelsActionLogStore()
    let viewModel = ModelsViewModel(
        profile: CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 80, performanceCores: 8),
        installerService: service,
        installedModelStore: store,
        actionLogStore: actionLog
    )

    viewModel.clearInstalledRecord()

    #expect(viewModel.installedRecord == nil)
    #expect(viewModel.statusMessage == "Installed model metadata cleared.")
    #expect(actionLog.entries.first?.category == "models.metadata.cleared")
}

private struct StubModelInstallerService: Installing {
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

private final class InMemorySingleInstalledModelStore: InstalledModelStoring {
    private(set) var record: InstalledModelRecord?

    init(record: InstalledModelRecord?) {
        self.record = record
    }

    func save(record: InstalledModelRecord) throws {
        self.record = record
    }

    func load() throws -> InstalledModelRecord {
        guard let record else { throw InstalledModelStoreError.notFound }
        return record
    }

    func loadIfAvailable() throws -> InstalledModelRecord? {
        record
    }

    func clear() throws {
        record = nil
    }
}

private final class InMemoryModelsActionLogStore: @unchecked Sendable, InstallerActionLogging {
    private(set) var entries: [InstallerActionLogEntry] = []

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
#endif
