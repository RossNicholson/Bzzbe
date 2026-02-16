import Combine
import Foundation

@MainActor
final class PrivacySettingsModel: ObservableObject {
    static let telemetryEnabledKey = "privacy.telemetryEnabled"
    static let diagnosticsEnabledKey = "privacy.diagnosticsEnabled"

    @Published var telemetryEnabled: Bool {
        didSet { defaults.set(telemetryEnabled, forKey: Self.telemetryEnabledKey) }
    }

    @Published var diagnosticsEnabled: Bool {
        didSet { defaults.set(diagnosticsEnabled, forKey: Self.diagnosticsEnabledKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        telemetryEnabled = defaults.object(forKey: Self.telemetryEnabledKey) as? Bool ?? false
        diagnosticsEnabled = defaults.object(forKey: Self.diagnosticsEnabledKey) as? Bool ?? false
    }
}
