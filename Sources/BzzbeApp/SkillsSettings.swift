import Combine
import Foundation

enum SkillsConfiguration {
    static let disabledSkillIDsKey = "skills.disabled.ids"
}

@MainActor
final class SkillsSettingsModel: ObservableObject {
    struct SkillRow: Identifiable, Equatable {
        let id: String
        let name: String
        let summary: String
        let sourceTitle: String
        let isAvailable: Bool
        let gatingIssues: [String]
        let isEnabled: Bool
    }

    @Published private(set) var skills: [SkillRow] = []
    @Published private(set) var directoryDiagnostics: [String] = []

    private let loader: SkillCatalogLoader
    private let directorySet: SkillDirectorySet
    private let defaults: UserDefaults

    init(
        loader: SkillCatalogLoader = SkillCatalogLoader(),
        directorySet: SkillDirectorySet = SkillDirectorySet.defaults(),
        defaults: UserDefaults = .standard
    ) {
        self.loader = loader
        self.directorySet = directorySet
        self.defaults = defaults
        refresh()
    }

    func refresh() {
        let descriptors = loader.load(directorySet: directorySet)
        let disabled = disabledSkillIDs
        skills = descriptors.map { descriptor in
            SkillRow(
                id: descriptor.id,
                name: descriptor.manifest.name,
                summary: descriptor.manifest.summary,
                sourceTitle: descriptor.source.title,
                isAvailable: descriptor.isAvailable,
                gatingIssues: descriptor.gatingIssues,
                isEnabled: !disabled.contains(descriptor.id)
            )
        }
        directoryDiagnostics = loader.directoryDiagnostics(directorySet: directorySet)
    }

    func setSkillEnabled(_ isEnabled: Bool, skillID: String) {
        var disabled = disabledSkillIDs
        if isEnabled {
            disabled.remove(skillID)
        } else {
            disabled.insert(skillID)
        }
        defaults.set(Array(disabled).sorted(), forKey: SkillsConfiguration.disabledSkillIDsKey)
        refresh()
    }

    private var disabledSkillIDs: Set<String> {
        let rawValue = defaults.array(forKey: SkillsConfiguration.disabledSkillIDsKey) as? [String] ?? []
        return Set(rawValue)
    }
}
