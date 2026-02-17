import Foundation

enum SkillSource: String, Equatable, CaseIterable, Sendable {
    case workspace
    case user
    case bundled

    var title: String {
        switch self {
        case .workspace:
            return "Workspace"
        case .user:
            return "User"
        case .bundled:
            return "Bundled"
        }
    }
}

struct SkillManifest: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let summary: String
    let requiredBinaries: [String]
    let requiredEnvironmentVariables: [String]
    let requiredFiles: [String]

    init(
        id: String,
        name: String,
        summary: String,
        requiredBinaries: [String] = [],
        requiredEnvironmentVariables: [String] = [],
        requiredFiles: [String] = []
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.requiredBinaries = requiredBinaries
        self.requiredEnvironmentVariables = requiredEnvironmentVariables
        self.requiredFiles = requiredFiles
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case requiredBinaries
        case requiredEnvironmentVariables
        case requiredFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        requiredBinaries = try container.decodeIfPresent([String].self, forKey: .requiredBinaries) ?? []
        requiredEnvironmentVariables = try container.decodeIfPresent([String].self, forKey: .requiredEnvironmentVariables) ?? []
        requiredFiles = try container.decodeIfPresent([String].self, forKey: .requiredFiles) ?? []
    }
}

struct SkillDescriptor: Identifiable, Equatable {
    let manifest: SkillManifest
    let source: SkillSource
    let directoryURL: URL
    let gatingIssues: [String]

    var id: String { manifest.id }
    var isAvailable: Bool { gatingIssues.isEmpty }
}

struct SkillDirectorySet {
    let workspaceSkillsDirectory: URL
    let userSkillsDirectory: URL
    let bundledSkillsDirectory: URL?

    static func defaults(
        currentWorkingDirectory: String = FileManager.default.currentDirectoryPath,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundle: Bundle = .main
    ) -> SkillDirectorySet {
        SkillDirectorySet(
            workspaceSkillsDirectory: URL(fileURLWithPath: currentWorkingDirectory).appendingPathComponent(".bzzbe/skills", isDirectory: true),
            userSkillsDirectory: homeDirectory.appendingPathComponent(".bzzbe/skills", isDirectory: true),
            bundledSkillsDirectory: bundle.resourceURL?.appendingPathComponent("skills", isDirectory: true)
        )
    }
}

protocol BinaryAvailabilityChecking {
    func isAvailable(binary: String) -> Bool
}

struct SystemBinaryAvailabilityChecker: BinaryAvailabilityChecking {
    func isAvailable(binary: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", binary]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct SkillCatalogLoader {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let binaryChecker: BinaryAvailabilityChecking
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        binaryChecker: BinaryAvailabilityChecking = SystemBinaryAvailabilityChecker(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.decoder = decoder
        self.binaryChecker = binaryChecker
        self.environment = environment
    }

    func load(directorySet: SkillDirectorySet) -> [SkillDescriptor] {
        let workspace = discoverSkills(in: directorySet.workspaceSkillsDirectory, source: .workspace)
        let user = discoverSkills(in: directorySet.userSkillsDirectory, source: .user)
        let bundled = discoverSkills(in: directorySet.bundledSkillsDirectory, source: .bundled)

        var selectedByID: [String: SkillDescriptor] = [:]
        for collection in [workspace, user, bundled] {
            for skill in collection where selectedByID[skill.id] == nil {
                selectedByID[skill.id] = skill
            }
        }

        return selectedByID.values.sorted { lhs, rhs in
            lhs.manifest.name.localizedCaseInsensitiveCompare(rhs.manifest.name) == .orderedAscending
        }
    }

    func directoryDiagnostics(directorySet: SkillDirectorySet) -> [String] {
        var diagnostics: [String] = []
        if !directoryExists(at: directorySet.workspaceSkillsDirectory) {
            diagnostics.append("Workspace skills directory missing: \(directorySet.workspaceSkillsDirectory.path)")
        }
        if !directoryExists(at: directorySet.userSkillsDirectory) {
            diagnostics.append("User skills directory missing: \(directorySet.userSkillsDirectory.path)")
        }
        if let bundledDirectory = directorySet.bundledSkillsDirectory, !directoryExists(at: bundledDirectory) {
            diagnostics.append("Bundled skills directory missing: \(bundledDirectory.path)")
        }
        return diagnostics
    }

    private func discoverSkills(in directory: URL?, source: SkillSource) -> [SkillDescriptor] {
        guard let directory, directoryExists(at: directory) else {
            return []
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var skills: [SkillDescriptor] = []
        for child in children where isDirectory(child) {
            let manifestURL = child.appendingPathComponent("skill.json", isDirectory: false)
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                continue
            }
            guard
                let data = try? Data(contentsOf: manifestURL),
                let manifest = try? decoder.decode(SkillManifest.self, from: data)
            else {
                continue
            }
            let issues = gatingIssues(for: manifest, skillDirectory: child)
            skills.append(
                SkillDescriptor(
                    manifest: manifest,
                    source: source,
                    directoryURL: child,
                    gatingIssues: issues
                )
            )
        }
        return skills
    }

    private func gatingIssues(for manifest: SkillManifest, skillDirectory: URL) -> [String] {
        var issues: [String] = []

        for binary in manifest.requiredBinaries where !binaryChecker.isAvailable(binary: binary) {
            issues.append("Missing required binary: \(binary)")
        }

        for variable in manifest.requiredEnvironmentVariables {
            let value = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                issues.append("Missing required environment variable: \(variable)")
            }
        }

        for file in manifest.requiredFiles {
            let pathURL: URL
            if file.hasPrefix("/") {
                pathURL = URL(fileURLWithPath: file)
            } else {
                pathURL = skillDirectory.appendingPathComponent(file, isDirectory: false)
            }
            if !fileManager.fileExists(atPath: pathURL.path) {
                issues.append("Missing required file: \(file)")
            }
        }

        return issues
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
