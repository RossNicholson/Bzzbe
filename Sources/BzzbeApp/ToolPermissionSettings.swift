import Combine
import CoreAgents
import Foundation

enum ToolPermissionConfiguration {
    static let profileKey = "tool.permission.profile"
}

protocol ToolPermissionProfileProviding {
    func currentProfile() -> AgentToolAccessLevel
}

struct DefaultsToolPermissionProfileProvider: ToolPermissionProfileProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentProfile() -> AgentToolAccessLevel {
        guard
            let rawValue = defaults.string(forKey: ToolPermissionConfiguration.profileKey),
            let profile = AgentToolAccessLevel(rawValue: rawValue)
        else {
            return .readOnly
        }
        return profile
    }
}

@MainActor
final class ToolPermissionSettingsModel: ObservableObject {
    @Published var selectedProfile: AgentToolAccessLevel {
        didSet {
            defaults.set(selectedProfile.rawValue, forKey: ToolPermissionConfiguration.profileKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if
            let rawValue = defaults.string(forKey: ToolPermissionConfiguration.profileKey),
            let profile = AgentToolAccessLevel(rawValue: rawValue)
        {
            selectedProfile = profile
        } else {
            selectedProfile = .readOnly
        }
    }
}
