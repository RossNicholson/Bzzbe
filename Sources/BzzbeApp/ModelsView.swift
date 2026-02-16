#if canImport(SwiftUI)
import CoreHardware
import CoreInstaller
import Foundation
import SwiftUI

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published private(set) var recommendation: InstallRecommendation
    @Published private(set) var compatibleCandidates: [ModelCandidate]
    @Published private(set) var installedRecord: InstalledModelRecord?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private let profile: CapabilityProfile
    private let installerService: Installing
    private let installedModelStore: InstalledModelStoring
    private let actionLogStore: InstallerActionLogging

    init(
        profile: CapabilityProfile,
        installerService: Installing = InstallerService(),
        installedModelStore: InstalledModelStoring = JSONInstalledModelStore.defaultStore(),
        actionLogStore: InstallerActionLogging = JSONInstallerActionLogStore.defaultStore()
    ) {
        self.profile = profile
        self.installerService = installerService
        self.installedModelStore = installedModelStore
        self.actionLogStore = actionLogStore
        self.recommendation = installerService.recommendedInstall(for: profile)
        self.compatibleCandidates = installerService.compatibleCandidates(for: profile)
        refreshInstalledRecord()
    }

    func refreshModelData() {
        recommendation = installerService.recommendedInstall(for: profile)
        compatibleCandidates = installerService.compatibleCandidates(for: profile)
        refreshInstalledRecord()
        statusMessage = "Model data refreshed."
    }

    func refreshInstalledRecord() {
        do {
            installedRecord = try installedModelStore.loadIfAvailable()
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load installed model metadata. \(error.localizedDescription)"
        }
    }

    func clearInstalledRecord() {
        do {
            try installedModelStore.clear()
            installedRecord = nil
            statusMessage = "Installed model metadata cleared."
            errorMessage = nil
            logAction(category: "models.metadata.cleared", message: "Cleared installed model metadata.")
        } catch {
            errorMessage = "Failed to clear installed model metadata. \(error.localizedDescription)"
        }
    }

    func compatibleCandidate(by id: String) -> ModelCandidate? {
        compatibleCandidates.first(where: { $0.id == id })
    }

    private func logAction(category: String, message: String) {
        let entry = InstallerActionLogEntry(category: category, message: message)
        try? actionLogStore.append(entry)
    }
}

struct ModelsView: View {
    @Binding private var preferredModelID: String
    private let onRequestSetupRerun: () -> Void
    @StateObject private var viewModel: ModelsViewModel

    init(
        profile: CapabilityProfile,
        preferredModelID: Binding<String>,
        onRequestSetupRerun: @escaping () -> Void
    ) {
        _preferredModelID = preferredModelID
        self.onRequestSetupRerun = onRequestSetupRerun
        _viewModel = StateObject(wrappedValue: ModelsViewModel(profile: profile))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                selectionCard
                installedCard
                catalogCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            syncPreferredModelSelectionIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models")
                .font(.largeTitle.bold())
            Text("Choose the default model for chat and tasks, and review installed metadata.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var selectionCard: some View {
        GroupBox("Default Model Selection") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Preferred model", selection: preferredSelectionBinding) {
                    ForEach(viewModel.compatibleCandidates, id: \.id) { candidate in
                        Text(candidatePickerLabel(candidate))
                            .tag(candidate.id)
                    }
                }
                .pickerStyle(.menu)

                if let selected = selectedCandidate {
                    Text("Selected: \(selected.displayName)")
                        .font(.headline)
                    Text("Tier: \(selected.tier.rawValue)")
                    Text("Approximate download: \(selected.approximateDownloadSizeGB, specifier: "%.1f")GB")
                    Text("Minimum memory: \(selected.minimumMemoryGB)GB")
                } else {
                    Text("No compatible model profile is currently available for this hardware.")
                        .foregroundStyle(.secondary)
                }

                if let recommended = viewModel.recommendation.candidate,
                   preferredModelID != recommended.id {
                    Text("Recommended for this Mac: \(recommended.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Use Recommended") {
                        if let recommendedID = viewModel.recommendation.candidate?.id {
                            preferredModelID = recommendedID
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.recommendation.candidate == nil)

                    Button("Run Setup Again") {
                        onRequestSetupRerun()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var installedCard: some View {
        GroupBox("Installed Model Metadata") {
            VStack(alignment: .leading, spacing: 8) {
                if let record = viewModel.installedRecord {
                    Text("Installed model: \(record.modelID)")
                        .font(.headline)
                    Text("Tier: \(record.tier)")
                    Text("Version: \(record.version)")
                    Text("Checksum: \(record.checksumSHA256)")
                    Text("Artifact path: \(record.artifactPath)")
                        .textSelection(.enabled)
                    Text("Installed at: \(record.installedAt, format: .dateTime.year().month().day().hour().minute().second())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No installed model metadata found.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Refresh") {
                        viewModel.refreshModelData()
                    }
                    .buttonStyle(.bordered)

                    Button("Clear Metadata", role: .destructive) {
                        viewModel.clearInstalledRecord()
                    }
                    .buttonStyle(.bordered)
                }

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var catalogCard: some View {
        GroupBox("Compatible Profiles") {
            if viewModel.compatibleCandidates.isEmpty {
                Text("No compatible model profiles found for the current hardware profile.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.compatibleCandidates, id: \.id) { candidate in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text("ID: \(candidate.id)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Tier: \(candidate.tier.rawValue) · \(candidate.approximateDownloadSizeGB, specifier: "%.1f")GB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if candidate.id != viewModel.compatibleCandidates.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var preferredSelectionBinding: Binding<String> {
        Binding(
            get: {
                if !preferredModelID.isEmpty {
                    return preferredModelID
                }
                return viewModel.recommendation.candidate?.id ?? ""
            },
            set: { preferredModelID = $0 }
        )
    }

    private var selectedCandidate: ModelCandidate? {
        viewModel.compatibleCandidate(by: preferredModelID)
            ?? viewModel.recommendation.candidate
    }

    private func candidatePickerLabel(_ candidate: ModelCandidate) -> String {
        if candidate.id == viewModel.recommendation.candidate?.id {
            return "\(candidate.displayName) (Recommended)"
        }
        return candidate.displayName
    }

    private func syncPreferredModelSelectionIfNeeded() {
        if let existing = viewModel.compatibleCandidate(by: preferredModelID) {
            preferredModelID = existing.id
            return
        }
        if let recommendedID = viewModel.recommendation.candidate?.id {
            preferredModelID = recommendedID
            return
        }
        if let firstCompatible = viewModel.compatibleCandidates.first?.id {
            preferredModelID = firstCompatible
        }
    }
}
#endif
