@testable import BzzbeApp
import Foundation
import Testing

@MainActor
@Test("PrivacySettingsModel defaults optional telemetry controls to disabled")
func privacySettingsDefaultsDisabled() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = PrivacySettingsModel(defaults: defaults)

    #expect(model.telemetryEnabled == false)
    #expect(model.diagnosticsEnabled == false)
}

@MainActor
@Test("PrivacySettingsModel persists explicit opt-in values")
func privacySettingsPersistsChoices() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = PrivacySettingsModel(defaults: defaults)
    model.telemetryEnabled = true
    model.diagnosticsEnabled = true

    let restored = PrivacySettingsModel(defaults: defaults)
    #expect(restored.telemetryEnabled == true)
    #expect(restored.diagnosticsEnabled == true)
}

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "BzzbeAppTests.Privacy.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Unable to create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
