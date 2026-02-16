import CoreHardware
import Foundation

struct AppState {
    enum Route: String, CaseIterable, Identifiable {
        case chat
        case tasks
        case models
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chat: return "Chat"
            case .tasks: return "Tasks"
            case .models: return "Models"
            case .settings: return "Settings"
            }
        }

        var subtitle: String {
            switch self {
            case .chat:
                return "Local chat interactions"
            case .tasks:
                return "Agent workflows (coming next phase)"
            case .models:
                return "Model management (coming next phase)"
            case .settings:
                return "App preferences and diagnostics"
            }
        }
    }

    var selectedRoute: Route = .chat
    var capabilityProfile: CapabilityProfile = DefaultHardwareProfiler().currentProfile()
}
