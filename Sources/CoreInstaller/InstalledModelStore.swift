import Foundation

public struct InstalledModelRecord: Sendable, Equatable, Codable {
    public let modelID: String
    public let tier: String
    public let artifactPath: String
    public let checksumSHA256: String
    public let version: String
    public let installedAt: Date

    public init(
        modelID: String,
        tier: String,
        artifactPath: String,
        checksumSHA256: String,
        version: String,
        installedAt: Date = Date()
    ) {
        self.modelID = modelID
        self.tier = tier
        self.artifactPath = artifactPath
        self.checksumSHA256 = checksumSHA256
        self.version = version
        self.installedAt = installedAt
    }
}

public enum InstalledModelStoreError: Error, Sendable, Equatable {
    case invalidStoreURL
    case notFound
    case decodeFailed
}

public protocol InstalledModelStoring {
    func save(record: InstalledModelRecord) throws
    func load() throws -> InstalledModelRecord
    func loadIfAvailable() throws -> InstalledModelRecord?
    func clear() throws
}

public struct JSONInstalledModelStore: InstalledModelStoring {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultStore(appName: String = "Bzzbe") -> JSONInstalledModelStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = base
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("installer", isDirectory: true)
            .appendingPathComponent("installed-model.json", isDirectory: false)
        return JSONInstalledModelStore(fileURL: fileURL)
    }

    public func save(record: InstalledModelRecord) throws {
        guard fileURL.isFileURL else {
            throw InstalledModelStoreError.invalidStoreURL
        }

        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() throws -> InstalledModelRecord {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw InstalledModelStoreError.notFound
        }

        let data = try Data(contentsOf: fileURL)
        guard let decoded = try? decoder.decode(InstalledModelRecord.self, from: data) else {
            throw InstalledModelStoreError.decodeFailed
        }
        return decoded
    }

    public func loadIfAvailable() throws -> InstalledModelRecord? {
        do {
            return try load()
        } catch InstalledModelStoreError.notFound {
            return nil
        }
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
