import CoreHardware

public enum ModelTier: String, Sendable {
    case small
    case balanced
    case highQuality = "high_quality"
}

public struct ModelCandidate: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let approximateDownloadSizeGB: Double
    public let minimumMemoryGB: Int
    public let tier: ModelTier

    public init(
        id: String,
        displayName: String,
        approximateDownloadSizeGB: Double,
        minimumMemoryGB: Int,
        tier: ModelTier
    ) {
        self.id = id
        self.displayName = displayName
        self.approximateDownloadSizeGB = max(0, approximateDownloadSizeGB)
        self.minimumMemoryGB = max(0, minimumMemoryGB)
        self.tier = tier
    }
}

public struct InstallRecommendation: Sendable, Equatable {
    public let tier: String
    public let candidate: ModelCandidate
    public let rationale: String

    public init(tier: String, candidate: ModelCandidate, rationale: String) {
        self.tier = tier
        self.candidate = candidate
        self.rationale = rationale
    }
}

public protocol Installing {
    func recommendedTier() -> InstallRecommendation
    func recommendedInstall(for profile: CapabilityProfile) -> InstallRecommendation
}

public struct InstallerService: Installing {
    public static let defaultCatalog: [ModelCandidate] = [
        .init(
            id: "llama3.2:3b-instruct-q4_K_M",
            displayName: "Llama 3.2 3B Instruct (Q4_K_M)",
            approximateDownloadSizeGB: 2.0,
            minimumMemoryGB: 8,
            tier: .small
        ),
        .init(
            id: "qwen2.5:7b-instruct-q4_K_M",
            displayName: "Qwen 2.5 7B Instruct (Q4_K_M)",
            approximateDownloadSizeGB: 4.7,
            minimumMemoryGB: 16,
            tier: .balanced
        ),
        .init(
            id: "gemma3:12b-it-q4_K_M",
            displayName: "Gemma 3 12B IT (Q4_K_M)",
            approximateDownloadSizeGB: 8.1,
            minimumMemoryGB: 24,
            tier: .highQuality
        )
    ]

    private let catalog: [ModelCandidate]

    public init(catalog: [ModelCandidate] = defaultCatalog) {
        self.catalog = catalog
    }

    public func recommendedTier() -> InstallRecommendation {
        let fallbackProfile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 64, performanceCores: 8)
        return recommendedInstall(for: fallbackProfile)
    }

    public func recommendedInstall(for profile: CapabilityProfile) -> InstallRecommendation {
        let targetTier: ModelTier
        if profile.memoryGB >= 24 {
            targetTier = .highQuality
        } else if profile.memoryGB >= 16 {
            targetTier = .balanced
        } else {
            targetTier = .small
        }

        let diskFiltered = catalog
            .filter { $0.minimumMemoryGB <= profile.memoryGB }
            .filter { profile.freeDiskGB >= Int(($0.approximateDownloadSizeGB * 2.0).rounded(.up)) }

        let chosen = diskFiltered.first(where: { $0.tier == targetTier })
            ?? diskFiltered.last
            ?? catalog.first!

        return InstallRecommendation(
            tier: chosen.tier.rawValue,
            candidate: chosen,
            rationale: "Selected \(chosen.displayName) for \(profile.memoryGB)GB RAM and \(profile.freeDiskGB)GB free disk."
        )
    }
}
