import Foundation

enum TaskApprovalConfiguration {
    static let alwaysAllowedTaskIDsKey = "task.approval.always_allowed_task_ids"
}

protocol TaskApprovalRuleProviding {
    func isAlwaysAllowed(taskID: String) -> Bool
    func allowAlways(taskID: String)
}

final class DefaultsTaskApprovalRuleProvider: TaskApprovalRuleProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isAlwaysAllowed(taskID: String) -> Bool {
        storedTaskIDs.contains(taskID)
    }

    func allowAlways(taskID: String) {
        var ids = storedTaskIDs
        ids.insert(taskID)
        defaults.set(Array(ids).sorted(), forKey: TaskApprovalConfiguration.alwaysAllowedTaskIDsKey)
    }

    private var storedTaskIDs: Set<String> {
        let values = defaults.array(forKey: TaskApprovalConfiguration.alwaysAllowedTaskIDsKey) as? [String] ?? []
        return Set(values)
    }
}
