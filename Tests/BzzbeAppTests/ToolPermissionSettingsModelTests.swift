@testable import BzzbeApp
import CoreAgents
import Foundation
import Testing

@MainActor
@Test("ToolPermissionSettingsModel defaults to read-only profile")
func toolPermissionDefaultsToReadOnly() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = ToolPermissionSettingsModel(defaults: defaults)
    #expect(model.selectedProfile == .readOnly)
}

@MainActor
@Test("ToolPermissionSettingsModel persists selected profile")
func toolPermissionPersistsSelection() {
    let (defaults, suiteName) = makeIsolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let model = ToolPermissionSettingsModel(defaults: defaults)
    model.selectedProfile = .advanced

    let restored = ToolPermissionSettingsModel(defaults: defaults)
    #expect(restored.selectedProfile == .advanced)
}

private func makeIsolatedDefaults() -> (UserDefaults, String) {
    let suiteName = "BzzbeAppTests.ToolPermission.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Unable to create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return (defaults, suiteName)
}
