#if canImport(SwiftUI)
import CoreHardware
import SwiftUI

struct AppShellView: View {
    @State private var appState = AppState()

    var body: some View {
        NavigationSplitView {
            List(AppState.Route.allCases, selection: routeBinding) { route in
                NavigationLink(value: route) {
                    Label(route.title, systemImage: icon(for: route))
                }
            }
            .navigationTitle("Bzzbe")
        } detail: {
            RouteDetailView(route: appState.selectedRoute, capabilityProfile: appState.capabilityProfile)
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

    var body: some View {
        switch route {
        case .chat:
            ChatView()
        case .tasks, .models, .settings:
            RoutePlaceholderView(
                title: route.title,
                subtitle: route.subtitle,
                content: content,
                capabilityProfile: route == .settings ? capabilityProfile : nil
            )
        }
    }

    private var content: String {
        switch route {
        case .chat:
            return "Chat shell ready. Streaming UI will be implemented in JOB-006."
        case .tasks:
            return "Tasks catalog placeholder. Agent templates will be added in a later phase."
        case .models:
            return "Model installation and management UI placeholder."
        case .settings:
            return "Settings placeholder for privacy controls and diagnostics."
        }
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
