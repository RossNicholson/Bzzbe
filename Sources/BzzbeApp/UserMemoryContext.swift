import Combine
import Foundation

struct MemoryContext: Equatable {
    let isEnabled: Bool
    let content: String
    let scope: MemoryNoteScope
    let notes: [MemoryNote]

    init(
        isEnabled: Bool,
        content: String,
        scope: MemoryNoteScope = .private,
        notes: [MemoryNote] = []
    ) {
        self.isEnabled = isEnabled
        self.content = content
        self.scope = scope
        self.notes = notes
    }
}

protocol MemoryContextProviding {
    func loadContext() -> MemoryContext
}

protocol MemoryNoteSearching {
    func searchNotes(query: String, scope: MemoryNoteScope, limit: Int) -> [MemoryNote]
}

enum UserMemoryConfiguration {
    static let enabledKey = "memory.context.enabled"
    static let scopeKey = "memory.context.scope"

    static func appDirectoryURL(
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) -> URL {
        let baseURL = appSupportDirectoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return baseURL.appendingPathComponent("Bzzbe", isDirectory: true)
    }

    static func memoryFileURL(
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) -> URL {
        appDirectoryURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        ).appendingPathComponent("MEMORY.md", isDirectory: false)
    }

    static func memoryNotesFileURL(
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) -> URL {
        appDirectoryURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        ).appendingPathComponent("MEMORY_NOTES.json", isDirectory: false)
    }
}

final class FileMemoryContextProvider: MemoryContextProviding, MemoryNoteSearching {
    private let defaults: UserDefaults
    private let memoryFileURL: URL
    private let fileManager: FileManager
    private let notesStore: MemoryNotesStoring

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil,
        notesStore: MemoryNotesStoring? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.memoryFileURL = UserMemoryConfiguration.memoryFileURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
        self.notesStore = notesStore ?? JSONMemoryNotesStore.defaultStore(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
    }

    func loadContext() -> MemoryContext {
        let enabled = defaults.object(forKey: UserMemoryConfiguration.enabledKey) as? Bool ?? false
        guard enabled else {
            return MemoryContext(isEnabled: false, content: "")
        }

        let scope = currentScope()
        let baseContent: String
        if fileManager.fileExists(atPath: memoryFileURL.path) {
            baseContent = (try? String(contentsOf: memoryFileURL, encoding: .utf8)) ?? ""
        } else {
            baseContent = ""
        }
        let scopedNotes = (try? notesStore.loadNotes())?
            .filter { $0.scope == scope }
            .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt } ?? []
        let notesSection = formatNotesForContext(scopedNotes)

        let mergedContent: String
        if notesSection.isEmpty {
            mergedContent = baseContent
        } else if baseContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergedContent = notesSection
        } else {
            mergedContent = baseContent + "\n\nDated memory notes:\n" + notesSection
        }

        return MemoryContext(
            isEnabled: true,
            content: mergedContent,
            scope: scope,
            notes: scopedNotes
        )
    }

    func searchNotes(query: String, scope: MemoryNoteScope, limit: Int) -> [MemoryNote] {
        let notes = (try? notesStore.loadNotes()) ?? []
        return MemorySearchIndex.search(query: query, notes: notes, scope: scope, limit: limit)
    }

    private func currentScope() -> MemoryNoteScope {
        guard
            let rawValue = defaults.string(forKey: UserMemoryConfiguration.scopeKey),
            let scope = MemoryNoteScope(rawValue: rawValue)
        else {
            return .private
        }
        return scope
    }

    private func formatNotesForContext(_ notes: [MemoryNote]) -> String {
        guard !notes.isEmpty else { return "" }
        return notes.map { note in
            let dateText = note.createdAt.formatted(date: .abbreviated, time: .shortened)
            return "- [\(dateText)] \(note.title): \(note.content)"
        }
        .joined(separator: "\n")
    }
}

@MainActor
final class UserMemorySettingsModel: ObservableObject {
    @Published var isMemoryEnabled: Bool {
        didSet {
            defaults.set(isMemoryEnabled, forKey: UserMemoryConfiguration.enabledKey)
        }
    }

    @Published var selectedScope: MemoryNoteScope {
        didSet {
            defaults.set(selectedScope.rawValue, forKey: UserMemoryConfiguration.scopeKey)
            refreshSearchResults()
        }
    }

    @Published var content: String
    @Published var noteTitle: String = ""
    @Published var noteContent: String = ""
    @Published var noteScope: MemoryNoteScope = .private
    @Published var noteSearchQuery: String = "" {
        didSet {
            refreshSearchResults()
        }
    }
    @Published private(set) var notes: [MemoryNote] = []
    @Published private(set) var searchResults: [MemoryNote] = []
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    var locationPath: String { memoryFileURL.path }
    var notesLocationPath: String { notesFileURL.path }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let memoryFileURL: URL
    private let notesFileURL: URL
    private let notesStore: MemoryNotesStoring

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil,
        notesStore: MemoryNotesStoring? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.memoryFileURL = UserMemoryConfiguration.memoryFileURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
        self.notesFileURL = UserMemoryConfiguration.memoryNotesFileURL(
            fileManager: fileManager,
            appSupportDirectoryURL: appSupportDirectoryURL
        )
        self.notesStore = notesStore ?? JSONMemoryNotesStore(
            fileURL: UserMemoryConfiguration.memoryNotesFileURL(
                fileManager: fileManager,
                appSupportDirectoryURL: appSupportDirectoryURL
            ),
            fileManager: fileManager
        )
        isMemoryEnabled = defaults.object(forKey: UserMemoryConfiguration.enabledKey) as? Bool ?? false
        if
            let rawScope = defaults.string(forKey: UserMemoryConfiguration.scopeKey),
            let parsedScope = MemoryNoteScope(rawValue: rawScope)
        {
            selectedScope = parsedScope
        } else {
            selectedScope = .private
        }
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

    func addNote() {
        let trimmedTitle = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = noteContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            errorMessage = "Note title and content are required."
            statusMessage = nil
            return
        }

        do {
            var updated = notes
            updated.append(
                MemoryNote(
                    id: UUID(),
                    createdAt: Date(),
                    scope: noteScope,
                    title: trimmedTitle,
                    content: trimmedContent
                )
            )
            try notesStore.saveNotes(updated.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt })
            noteTitle = ""
            noteContent = ""
            reload()
            statusMessage = "Added memory note."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to add memory note. \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    func deleteNote(_ noteID: UUID) {
        do {
            let remaining = notes.filter { $0.id != noteID }
            try notesStore.saveNotes(remaining)
            reload()
            statusMessage = "Deleted memory note."
            errorMessage = nil
        } catch {
            errorMessage = "Failed to delete memory note. \(error.localizedDescription)"
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
            notes = try notesStore.loadNotes().sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
            refreshSearchResults()
            statusMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load memory. \(error.localizedDescription)"
            statusMessage = nil
        }
    }

    private func refreshSearchResults() {
        let query = noteSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchResults = MemorySearchIndex.search(
            query: query,
            notes: notes,
            scope: selectedScope,
            limit: 8
        )
    }
}
