#if canImport(SwiftUI)
@testable import BzzbeApp
import Foundation
import Testing

@MainActor
@Test("SkillsSettingsModel persists enabled/disabled selections")
func skillsSettingsModelPersistsSelections() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("skills-settings-\(UUID().uuidString)", isDirectory: true)
    let workspaceDirectory = root.appendingPathComponent("workspace", isDirectory: true)
    let userDirectory = root.appendingPathComponent("user", isDirectory: true)

    try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    try writeSkill(
        at: workspaceDirectory,
        folderName: "writer",
        manifest: SkillManifest(id: "writer", name: "Writer", summary: "Drafts copy")
    )

    let suiteName = "BzzbeAppTests.Skills.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create UserDefaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let loader = SkillCatalogLoader(
        fileManager: fileManager,
        binaryChecker: StubBinaryChecker(availableBinaries: []),
        environment: [:]
    )
    let directorySet = SkillDirectorySet(
        workspaceSkillsDirectory: workspaceDirectory,
        userSkillsDirectory: userDirectory,
        bundledSkillsDirectory: nil
    )

    let model = SkillsSettingsModel(
        loader: loader,
        directorySet: directorySet,
        defaults: defaults
    )
    #expect(model.skills.first?.id == "writer")
    #expect(model.skills.first?.isEnabled == true)

    model.setSkillEnabled(false, skillID: "writer")
    #expect(model.skills.first?.isEnabled == false)

    let restored = SkillsSettingsModel(
        loader: loader,
        directorySet: directorySet,
        defaults: defaults
    )
    #expect(restored.skills.first?.isEnabled == false)
}

private struct StubBinaryChecker: BinaryAvailabilityChecking {
    let availableBinaries: Set<String>

    init(availableBinaries: Set<String>) {
        self.availableBinaries = availableBinaries
    }

    func isAvailable(binary: String) -> Bool {
        availableBinaries.contains(binary)
    }
}

private func writeSkill(at root: URL, folderName: String, manifest: SkillManifest) throws {
    let fileManager = FileManager.default
    let skillDirectory = root.appendingPathComponent(folderName, isDirectory: true)
    try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    let manifestURL = skillDirectory.appendingPathComponent("skill.json", isDirectory: false)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: manifestURL)
}
#endif
