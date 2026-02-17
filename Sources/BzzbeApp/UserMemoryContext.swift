import Combine
import Foundation

struct MemoryContext: Equatable {
    let isEnabled: Bool
    let content: String
}

protocol MemoryContextProviding {
    func loadContext() -> MemoryContext
}

enum UserMemoryConfiguration {
    static let enabledKey = "memory.context.enabled"

    static func memoryFileURL(
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) -> URL {
        let baseURL = appSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let appDirectoryURL = baseURL.appendingPathComponent("Bzzbe", isDirectory: true)
        return appDirectoryURL.appendingPathComponent("MEMORY.md", isDirectory: false)
    }
}

final class FileMemoryContextProvider: MemoryContextProviding {
    private let defaults: UserDefaults
    private let memoryFileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var cachedContext: MemoryContext?
    private var cachedModificationDate: Date?
    private var cachedFileSize: Int64?

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.memoryFileURL = UserMemoryConfiguration.memoryFileURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
    }

    func loadContext() -> MemoryContext {
        let enabled = defaults.object(forKey: UserMemoryConfiguration.enabledKey) as? Bool ?? false
        guard enabled else {
            return MemoryContext(isEnabled: false, content: "")
        }

        let resourceValues = try? memoryFileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modificationDate = resourceValues?.contentModificationDate
        let fileSize = resourceValues?.fileSize.map(Int64.init)

        lock.lock()
        defer { lock.unlock() }

        if let cachedContext,
           cachedModificationDate == modificationDate,
           cachedFileSize == fileSize {
            return cachedContext
        }

        let content: String
        if fileManager.fileExists(atPath: memoryFileURL.path) {
            content = (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
        } else {
            content = ""
        }

        let context = MemoryContext(isEnabled: true, content: content)
        cachedContext = context
        cachedModificationDate = modificationDate
        cachedFileSize = fileSize
        return context
    }
}

@MainActor
final class UserMemorySettingsModel: ObservableObject {
    @Published var isMemoryEnabled: Bool {
        didSet {
            defaults.set(isMemoryEnabled, forKey: UserMemoryConfiguration.enabledKey)
        }
    }

    @Published var content: String
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    var locationPath: String { memoryFileURL.path }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let memoryFileURL: URL

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.memoryFileURL = UserMemoryConfiguration.memoryFileURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
        isMemoryEnabled = defaults.object(forKey: UserMemoryConfiguration.enabledKey) as? Bool ?? false
        content = ""
        reload()
    }

    func save() {
        do {
            let directoryURL = memoryFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try content.write(to: memoryFileURL, atomically: true, encoding: .utf8)
            statusMessage = "Saved memory to \(memoryFileURL.path)"
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save memory. \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    func reload() {
        do {
            if fileManager.fileExists(atPath: memoryFileURL.path) {
                content = try String(contentsOf: memoryFileURL, encoding: .utf8)
            } else {
                content = ""
            }
            statusMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load memory. \(error.localizedDescription)"
            statusMessage = nil
        }
    }
}
