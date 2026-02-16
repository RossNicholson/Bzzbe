#if canImport(SwiftUI)
import CoreHardware
import CoreInference
import CoreInstaller
import SwiftUI

struct AppShellView: View {
    @State private var appState = AppState()
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

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
    let onRequestSetupRerun: () -> Void

    var body: some View {
        switch route {
        case .chat:
            ChatView(onRequestSetupRerun: onRequestSetupRerun)
        case .tasks:
            TaskWorkspaceView(model: defaultModel)
        case .models:
            RoutePlaceholderView(
                title: route.title,
                subtitle: route.subtitle,
                content: content,
                capabilityProfile: nil
            )
        case .settings:
            SettingsView(capabilityProfile: capabilityProfile)
        }
    }

    private var content: String {
        switch route {
        case .chat:
            return "Chat shell ready. Streaming UI will be implemented in JOB-006."
        case .tasks:
            return ""
        case .models:
            return "Initial model setup is available at first launch. Ongoing model management UI is next phase work."
        case .settings:
            return ""
        }
    }

    private var defaultModel: InferenceModelDescriptor {
        InferenceModelDescriptor(
            identifier: "qwen3:8b",
            displayName: "Qwen 3 8B",
            contextWindow: 32_768
        )
    }
}

private struct RoutePlaceholderView: View {
    let title: String
    let subtitle: String
    let content: String
    let capabilityProfile: CapabilityProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)

            Divider()

            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)

            if let capabilityProfile {
                CapabilityDebugView(profile: capabilityProfile)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SettingsView: View {
    let capabilityProfile: CapabilityProfile
    @StateObject private var privacySettings = PrivacySettingsModel()
    @StateObject private var actionLogModel = InstallerActionLogModel()

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
