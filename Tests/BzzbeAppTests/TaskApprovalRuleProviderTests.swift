#if canImport(SwiftUI)
@testable import BzzbeApp
import Foundation
import Testing

@Test("DefaultsTaskApprovalRuleProvider persists always-allow decisions")
func defaultsTaskApprovalRuleProviderPersistsAllowlist() {
    let suiteName = "BzzbeAppTests.TaskApproval.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create UserDefaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let provider = DefaultsTaskApprovalRuleProvider(defaults: defaults)
    #expect(provider.isAlwaysAllowed(taskID: "organize_files_plan") == false)

    provider.allowAlways(taskID: "organize_files_plan")

    let restored = DefaultsTaskApprovalRuleProvider(defaults: defaults)
    #expect(restored.isAlwaysAllowed(taskID: "organize_files_plan") == true)
}
#endif
