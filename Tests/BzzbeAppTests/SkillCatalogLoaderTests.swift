#if canImport(SwiftUI)
@testable import BzzbeApp
import Foundation
import Testing

@Test("SkillCatalogLoader applies source precedence workspace > user > bundled")
func skillCatalogLoaderAppliesSourcePrecedence() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("skill-loader-\(UUID().uuidString)", isDirectory: true)
    let workspaceDirectory = root.appendingPathComponent("workspace", isDirectory: true)
    let userDirectory = root.appendingPathComponent("user", isDirectory: true)
    let bundledDirectory = root.appendingPathComponent("bundled", isDirectory: true)

    try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: bundledDirectory, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    try writeSkill(
        at: workspaceDirectory,
        folderName: "writer",
        manifest: SkillManifest(id: "writer", name: "Writer Workspace", summary: "Workspace variant")
    )
    try writeSkill(
        at: userDirectory,
        folderName: "writer",
        manifest: SkillManifest(id: "writer", name: "Writer User", summary: "User variant")
    )
    try writeSkill(
        at: bundledDirectory,
        folderName: "writer",
        manifest: SkillManifest(id: "writer", name: "Writer Bundled", summary: "Bundled variant")
    )

    let loader = SkillCatalogLoader(
        fileManager: fileManager,
        binaryChecker: StubBinaryChecker(availableBinaries: []),
        environment: [:]
    )
    let skills = loader.load(
        directorySet: SkillDirectorySet(
            workspaceSkillsDirectory: workspaceDirectory,
            userSkillsDirectory: userDirectory,
            bundledSkillsDirectory: bundledDirectory
        )
    )

    #expect(skills.count == 1)
    #expect(skills.first?.source == .workspace)
    #expect(skills.first?.manifest.name == "Writer Workspace")
}

@Test("SkillCatalogLoader enforces metadata gating requirements")
func skillCatalogLoaderEnforcesMetadataGating() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("skill-gating-\(UUID().uuidString)", isDirectory: true)
    let workspaceDirectory = root.appendingPathComponent("workspace", isDirectory: true)
    let userDirectory = root.appendingPathComponent("user", isDirectory: true)

    try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
    defer {
        try? fileManager.removeItem(at: root)
    }

    try writeSkill(
        at: workspaceDirectory,
        folderName: "ops",
        manifest: SkillManifest(
            id: "ops",
            name: "Ops Skill",
            summary: "Requires runtime deps",
            requiredBinaries: ["missing-binary"],
            requiredEnvironmentVariables: ["API_TOKEN"],
            requiredFiles: ["config.toml"]
        )
    )

    let loader = SkillCatalogLoader(
        fileManager: fileManager,
        binaryChecker: StubBinaryChecker(availableBinaries: []),
        environment: [:]
    )
    let skills = loader.load(
        directorySet: SkillDirectorySet(
            workspaceSkillsDirectory: workspaceDirectory,
            userSkillsDirectory: userDirectory,
            bundledSkillsDirectory: nil
        )
    )

    #expect(skills.count == 1)
    #expect(skills.first?.isAvailable == false)
    #expect(skills.first?.gatingIssues.contains(where: { $0.contains("missing-binary") }) == true)
    #expect(skills.first?.gatingIssues.contains(where: { $0.contains("API_TOKEN") }) == true)
    #expect(skills.first?.gatingIssues.contains(where: { $0.contains("config.toml") }) == true)
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
