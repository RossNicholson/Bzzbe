#if canImport(SwiftUI)
import CoreHardware
import CoreInference
import CoreInstaller
import SwiftUI

struct AppShellView: View {
    @State private var appState = AppState()
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false
    @AppStorage("preferredModelID") private var preferredModelID = ""

    var body: some View {
        NavigationSplitView {
            List(AppState.Route.allCases, selection: routeBinding) { route in
                NavigationLink(value: route) {
                    Label(route.title, systemImage: icon(for: route))
                }
            }
            .navigationTitle("Bzzbe")
        } detail: {
            RouteDetailView(
                route: appState.selectedRoute,
                capabilityProfile: appState.capabilityProfile,
                preferredModelID: $preferredModelID,
                onRequestSetupRerun: { hasCompletedInitialSetup = false }
            )
        }
    }

    private var routeBinding: Binding<AppState.Route?> {
        Binding(
            get: { appState.selectedRoute },
            set: { appState.selectedRoute = $0 ?? .chat }
        )
    }

    private func icon(for route: AppState.Route) -> String {
        switch route {
        case .chat: return "bubble.left.and.bubble.right"
        case .tasks: return "list.bullet.clipboard"
        case .models: return "cube.box"
        case .settings: return "gear"
        }
    }
}

private struct RouteDetailView: View {
    let route: AppState.Route
    let capabilityProfile: CapabilityProfile
    @Binding var preferredModelID: String
    let onRequestSetupRerun: () -> Void

    var body: some View {
        Group {
            switch route {
            case .chat:
                ChatView(model: selectedModel, onRequestSetupRerun: onRequestSetupRerun)
                    .id("chat-\(selectedModel.identifier)")
            case .tasks:
                TaskWorkspaceView(model: selectedModel)
                    .id("tasks-\(selectedModel.identifier)")
            case .models:
                ModelsView(
                    profile: capabilityProfile,
                    preferredModelID: $preferredModelID,
                    onRequestSetupRerun: onRequestSetupRerun
                )
            case .settings:
                SettingsView(capabilityProfile: capabilityProfile)
            }
        }
        .onAppear {
            syncPreferredModelIfNeeded()
        }
    }

    private var selectedModel: InferenceModelDescriptor {
        if let selectedCandidate = selectedCandidate {
            return modelDescriptor(from: selectedCandidate)
        }
        if !preferredModelID.isEmpty {
            return InferenceModelDescriptor(
                identifier: preferredModelID,
                displayName: preferredModelID,
                contextWindow: 32_768
            )
        }
        return InferenceModelDescriptor(
            identifier: "qwen3:8b",
            displayName: "Qwen 3 8B",
            contextWindow: 32_768
        )
    }

    private var selectedCandidate: ModelCandidate? {
        if let preferredCandidate = InstallerService.defaultCatalog.first(where: { $0.id == preferredModelID }) {
            return preferredCandidate
        }

        return InstallerService()
            .recommendedInstall(for: capabilityProfile)
            .candidate
            ?? InstallerService.defaultCatalog.first
    }

    private func modelDescriptor(from candidate: ModelCandidate) -> InferenceModelDescriptor {
        InferenceModelDescriptor(
            identifier: candidate.id,
            displayName: candidate.displayName,
            contextWindow: 32_768
        )
    }

    private func syncPreferredModelIfNeeded() {
        if !preferredModelID.isEmpty {
            return
        }
        if let recommendedID = InstallerService().recommendedInstall(for: capabilityProfile).candidate?.id {
            preferredModelID = recommendedID
            return
        }
        if let firstCandidateID = InstallerService.defaultCatalog.first?.id {
            preferredModelID = firstCandidateID
        }
    }
}

private struct SettingsView: View {
    let capabilityProfile: CapabilityProfile
    @StateObject private var privacySettings = PrivacySettingsModel()
    @StateObject private var actionLogModel = InstallerActionLogModel()
    @StateObject private var memorySettings = UserMemorySettingsModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.largeTitle.bold())
                Text("Privacy, consent, and diagnostics")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                GroupBox("Local-first data policy") {
                    Text(
                        "Bzzbe keeps prompts, conversation history, and model execution local to this Mac by default. "
                            + "Optional telemetry and diagnostics are disabled unless you explicitly enable them."
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Consent controls") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Share anonymous usage telemetry (optional)", isOn: $privacySettings.telemetryEnabled)
                        Toggle("Share crash diagnostics (optional)", isOn: $privacySettings.diagnosticsEnabled)
                        Text("Default for both controls: Off")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Current privacy status") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Usage telemetry: \(privacySettings.telemetryEnabled ? "Enabled" : "Disabled")")
                        Text("Crash diagnostics: \(privacySettings.diagnosticsEnabled ? "Enabled" : "Disabled")")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Personal memory") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use personal memory context in chat", isOn: $memorySettings.isMemoryEnabled)
                        Text(
                            "Store user preferences, writing style, project context, or standing instructions. "
                                + "This file stays local and is injected as system context when enabled."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        Text("File: \(memorySettings.locationPath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        TextEditor(text: $memorySettings.content)
                            .font(.body)
                            .frame(minHeight: 140)

                        HStack(spacing: 10) {
                            Button("Save Memory") {
                                memorySettings.save()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reload from Disk") {
                                memorySettings.reload()
                            }
                            .buttonStyle(.bordered)
                        }

                        if let statusMessage = memorySettings.statusMessage {
                            Text(statusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let errorMessage = memorySettings.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Installer and model action log") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button("Refresh Log") {
                                actionLogModel.refresh()
                            }
                            .buttonStyle(.bordered)

                            Button("Export as Text") {
                                actionLogModel.exportToDownloads()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if let exportStatusMessage = actionLogModel.exportStatusMessage {
                            Text(exportStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let errorMessage = actionLogModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if actionLogModel.entries.isEmpty {
                            Text("No installer/model actions recorded yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(actionLogModel.entries.prefix(20))) { entry in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("[\(entry.category)] \(entry.message)")
                                            .font(.footnote)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(entry.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if entry.id != actionLogModel.entries.prefix(20).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CapabilityDebugView(profile: capabilityProfile)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            actionLogModel.refresh()
        }
    }
}

private struct CapabilityDebugView: View {
    let profile: CapabilityProfile

    var body: some View {
        GroupBox("Hardware Profile (Debug)") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Architecture: \(profile.architecture)")
                Text("Memory (GB): \(profile.memoryGB)")
                Text("Free Disk (GB): \(profile.freeDiskGB)")
                Text("CPU Cores: \(profile.performanceCores)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
    }
}
#endif
