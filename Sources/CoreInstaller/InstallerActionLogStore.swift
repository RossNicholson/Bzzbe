import Foundation

public struct InstallerActionLogEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
    }
}

public protocol InstallerActionLogging: Sendable {
    func append(_ entry: InstallerActionLogEntry) throws
    func listEntries(limit: Int?) throws -> [InstallerActionLogEntry]
    func exportText(limit: Int?) throws -> String
}

public final class JSONInstallerActionLogStore: @unchecked Sendable, InstallerActionLogging {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let formatter: ISO8601DateFormatter

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
    }

    public static func defaultStore(appName: String = "Bzzbe") -> JSONInstallerActionLogStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let root = base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("installer", isDirectory: true)
        let fileURL = root.appendingPathComponent("action-log.json", isDirectory: false)
        return JSONInstallerActionLogStore(fileURL: fileURL)
    }

    public func append(_ entry: InstallerActionLogEntry) throws {
        var entries = try loadEntries()
        entries.append(entry)
        try save(entries)
    }

    public func listEntries(limit: Int? = nil) throws -> [InstallerActionLogEntry] {
        var entries = try loadEntries()
        entries.sort { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp > rhs.timestamp
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }

        guard let limit, limit >= 0 else { return entries }
        return Array(entries.prefix(limit))
    }

    public func exportText(limit: Int? = nil) throws -> String {
        let entries = try listEntries(limit: limit)
        guard !entries.isEmpty else { return "No installer/model actions have been recorded yet.\n" }

        let lines = entries.map { entry in
            let timestamp = formatter.string(from: entry.timestamp)
            return "[\(timestamp)] \(entry.category): \(entry.message)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func loadEntries() throws -> [InstallerActionLogEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([InstallerActionLogEntry].self, from: data)
    }

    private func save(_ entries: [InstallerActionLogEntry]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
