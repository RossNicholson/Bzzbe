import CoreAgents
import Foundation

struct ToolPermissionPolicyLayer: Equatable {
    let name: String
    let requiredProfile: AgentToolAccessLevel
    let activeProfile: AgentToolAccessLevel

    var isSatisfied: Bool {
        activeProfile.satisfies(requiredProfile)
    }
}

struct ToolPermissionEvaluation: Equatable {
    let activeProfile: AgentToolAccessLevel
    let effectiveRequiredProfile: AgentToolAccessLevel
    let layers: [ToolPermissionPolicyLayer]

    var isAllowed: Bool {
        layers.allSatisfy(\.isSatisfied)
    }

    var failureReason: String? {
        guard let failedLayer = layers.first(where: { !$0.isSatisfied }) else {
            return nil
        }
        return "Task blocked by \(failedLayer.name): requires \(failedLayer.requiredProfile.title), current profile is \(activeProfile.title)."
    }

    var explanation: String {
        layers
            .map { layer in
                let status = layer.isSatisfied ? "ok" : "blocked"
                return "\(layer.name): \(status) (\(layer.requiredProfile.title))"
            }
            .joined(separator: " · ")
    }
}

struct ToolPermissionPolicyPipeline {
    private let minimumProfileByTaskID: [String: AgentToolAccessLevel]

    init(minimumProfileByTaskID: [String: AgentToolAccessLevel] = [:]) {
        self.minimumProfileByTaskID = minimumProfileByTaskID
    }

    func evaluate(task: AgentTaskTemplate, activeProfile: AgentToolAccessLevel) -> ToolPermissionEvaluation {
        let taskRequired = task.requiredToolAccess
        let policyRequired = minimumProfileByTaskID[task.id] ?? .readOnly

        let effectiveRequired: AgentToolAccessLevel
        if policyRequired.rank > taskRequired.rank {
            effectiveRequired = policyRequired
        } else {
            effectiveRequired = taskRequired
        }

        let layers = [
            ToolPermissionPolicyLayer(
                name: "Task requirement",
                requiredProfile: taskRequired,
                activeProfile: activeProfile
            ),
            ToolPermissionPolicyLayer(
                name: "Policy minimum",
                requiredProfile: policyRequired,
                activeProfile: activeProfile
            )
        ]

        return ToolPermissionEvaluation(
            activeProfile: activeProfile,
            effectiveRequiredProfile: effectiveRequired,
            layers: layers
        )
    }
}
