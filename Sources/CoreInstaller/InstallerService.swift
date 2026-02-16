import CoreHardware
import Foundation

public enum ModelTier: String, Sendable {
    case small
    case balanced
    case highQuality = "high_quality"
}

public struct ProviderArtifactSource: Sendable, Equatable {
    public let providerName: String
    public let artifactURL: URL
    public let checksumSHA256: String?
    public let licenseURL: URL?

    public init(
        providerName: String,
        artifactURL: URL,
        checksumSHA256: String? = nil,
        licenseURL: URL? = nil
    ) {
        self.providerName = providerName
        self.artifactURL = artifactURL
        self.checksumSHA256 = checksumSHA256
        self.licenseURL = licenseURL
    }
}

public enum ModelInstallStrategy: Sendable, Equatable {
    case runtimeRegistryPull
    case providerArtifact(ProviderArtifactSource)
}

public struct ModelCandidate: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let approximateDownloadSizeGB: Double
    public let minimumMemoryGB: Int
    public let tier: ModelTier
    public let installStrategy: ModelInstallStrategy

    public init(
        id: String,
        displayName: String,
        approximateDownloadSizeGB: Double,
        minimumMemoryGB: Int,
        tier: ModelTier,
        installStrategy: ModelInstallStrategy = .runtimeRegistryPull
    ) {
        self.id = id
        self.displayName = displayName
        self.approximateDownloadSizeGB = max(0, approximateDownloadSizeGB)
        self.minimumMemoryGB = max(0, minimumMemoryGB)
        self.tier = tier
        self.installStrategy = installStrategy
    }
}

public struct InstallRecommendation: Sendable, Equatable {
    public let status: InstallRecommendationStatus
    public let tier: String?
    public let candidate: ModelCandidate?
    public let rationale: String
    public let minimumRequiredMemoryGB: Int?
    public let minimumRequiredDiskGB: Int?

    public init(
        status: InstallRecommendationStatus,
        tier: String? = nil,
        candidate: ModelCandidate? = nil,
        rationale: String,
        minimumRequiredMemoryGB: Int? = nil,
        minimumRequiredDiskGB: Int? = nil
    ) {
        self.status = status
        self.tier = tier
        self.candidate = candidate
        self.rationale = rationale
        self.minimumRequiredMemoryGB = minimumRequiredMemoryGB
        self.minimumRequiredDiskGB = minimumRequiredDiskGB
    }
}

public enum InstallRecommendationStatus: String, Sendable, Equatable {
    case ready
    case insufficientResources = "insufficient_resources"
}

public protocol Installing {
    func recommendedTier() -> InstallRecommendation
    func recommendedInstall(for profile: CapabilityProfile) -> InstallRecommendation
    func compatibleCandidates(for profile: CapabilityProfile) -> [ModelCandidate]
}

public struct InstallerService: Installing {
    public static let defaultCatalog: [ModelCandidate] = [
        .init(
            id: "qwen3:4b",
            displayName: "Qwen 3 4B",
            approximateDownloadSizeGB: 2.6,
            minimumMemoryGB: 8,
            tier: .small,
            installStrategy: .providerArtifact(
                ProviderArtifactSource(
                    providerName: "Hugging Face (bartowski)",
                    artifactURL: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3-4B-GGUF/resolve/main/Qwen_Qwen3-4B-Q4_K_M.gguf")!,
                    licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-4B-GGUF")
                )
            )
        ),
        .init(
            id: "phi4-mini:3.8b-instruct-q4_K_M",
            displayName: "Phi-4 Mini 3.8B Instruct (Q4_K_M)",
            approximateDownloadSizeGB: 2.5,
            minimumMemoryGB: 8,
            tier: .small
        ),
        .init(
            id: "qwen3:8b",
            displayName: "Qwen 3 8B",
            approximateDownloadSizeGB: 5.2,
            minimumMemoryGB: 16,
            tier: .balanced,
            installStrategy: .providerArtifact(
                ProviderArtifactSource(
                    providerName: "Hugging Face (bartowski)",
                    artifactURL: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3-8B-GGUF/resolve/main/Qwen_Qwen3-8B-Q4_K_M.gguf")!,
                    licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-8B-GGUF")
                )
            )
        ),
        .init(
            id: "qwen2.5:7b-instruct-q4_K_M",
            displayName: "Qwen 2.5 7B Instruct (Q4_K_M)",
            approximateDownloadSizeGB: 4.7,
            minimumMemoryGB: 16,
            tier: .balanced
        ),
        .init(
            id: "qwen3:14b",
            displayName: "Qwen 3 14B",
            approximateDownloadSizeGB: 9.3,
            minimumMemoryGB: 24,
            tier: .highQuality,
            installStrategy: .providerArtifact(
                ProviderArtifactSource(
                    providerName: "Hugging Face (bartowski)",
                    artifactURL: URL(string: "https://huggingface.co/bartowski/Qwen_Qwen3-14B-GGUF/resolve/main/Qwen_Qwen3-14B-Q4_K_M.gguf")!,
                    licenseURL: URL(string: "https://huggingface.co/Qwen/Qwen3-14B-GGUF")
                )
            )
        ),
        .init(
            id: "gemma3:12b-it-q4_K_M",
            displayName: "Gemma 3 12B IT (Q4_K_M)",
            approximateDownloadSizeGB: 8.1,
            minimumMemoryGB: 24,
            tier: .highQuality,
            installStrategy: .providerArtifact(
                ProviderArtifactSource(
                    providerName: "Hugging Face (bartowski)",
                    artifactURL: URL(string: "https://huggingface.co/bartowski/google_gemma-3-12b-it-qat-GGUF/resolve/main/google_gemma-3-12b-it-qat-Q4_0.gguf")!,
                    licenseURL: URL(string: "https://huggingface.co/google/gemma-3-12b-it-qat-q4_0-gguf")
                )
            )
        )
    ]

    private let catalog: [ModelCandidate]

    public init(catalog: [ModelCandidate] = defaultCatalog) {
        self.catalog = catalog.isEmpty ? Self.defaultCatalog : catalog
    }

    public func recommendedTier() -> InstallRecommendation {
        let fallbackProfile = CapabilityProfile(architecture: "arm64", memoryGB: 16, freeDiskGB: 64, performanceCores: 8)
        return recommendedInstall(for: fallbackProfile)
    }

    public func compatibleCandidates(for profile: CapabilityProfile) -> [ModelCandidate] {
        memoryCompatibleCandidates(for: profile)
            .filter { profile.freeDiskGB >= Self.requiredDiskGB(for: $0) }
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

        let memoryFiltered = memoryCompatibleCandidates(for: profile)
        let diskFiltered = compatibleCandidates(for: profile)

        if let chosen = diskFiltered.first(where: { $0.tier == targetTier }) ?? diskFiltered.last {
            return InstallRecommendation(
                status: .ready,
                tier: chosen.tier.rawValue,
                candidate: chosen,
                rationale: "Selected \(chosen.displayName) for \(profile.memoryGB)GB RAM and \(profile.freeDiskGB)GB free disk."
            )
        }

        let requirementSource = memoryFiltered.isEmpty ? catalog : memoryFiltered
        let requirementCandidate = requirementSource.min { lhs, rhs in
            if lhs.minimumMemoryGB != rhs.minimumMemoryGB {
                return lhs.minimumMemoryGB < rhs.minimumMemoryGB
            }
            return lhs.approximateDownloadSizeGB < rhs.approximateDownloadSizeGB
        }

        let minimumMemory = requirementCandidate?.minimumMemoryGB
        let minimumDisk = requirementCandidate.map { Self.requiredDiskGB(for: $0) }

        return InstallRecommendation(
            status: .insufficientResources,
            rationale: "No compatible model for \(profile.memoryGB)GB RAM and \(profile.freeDiskGB)GB free disk.",
            minimumRequiredMemoryGB: minimumMemory,
            minimumRequiredDiskGB: minimumDisk
        )
    }

    private func memoryCompatibleCandidates(for profile: CapabilityProfile) -> [ModelCandidate] {
        catalog.filter { $0.minimumMemoryGB <= profile.memoryGB }
    }

    private static func requiredDiskGB(for candidate: ModelCandidate) -> Int {
        Int((candidate.approximateDownloadSizeGB * 2.0).rounded(.up))
    }
}
