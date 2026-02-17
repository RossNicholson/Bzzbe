import Foundation

enum MemoryNoteScope: String, Codable, Equatable, CaseIterable {
    case `private` = "private"
    case shared = "shared"

    var title: String {
        switch self {
        case .private:
            return "Private"
        case .shared:
            return "Shared"
        }
    }
}

struct MemoryNote: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let scope: MemoryNoteScope
    let title: String
    let content: String
}

protocol MemoryNotesStoring {
    func loadNotes() throws -> [MemoryNote]
    func saveNotes(_ notes: [MemoryNote]) throws
}

struct JSONMemoryNotesStore: MemoryNotesStoring {
    let fileURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    static func defaultStore(
        fileManager: FileManager = .default,
        appSupportDirectoryURL: URL? = nil
    ) -> JSONMemoryNotesStore {
        JSONMemoryNotesStore(
            fileURL: UserMemoryConfiguration.memoryNotesFileURL(
                fileManager: fileManager,
                appSupportDirectoryURL: appSupportDirectoryURL
            ),
            fileManager: fileManager
        )
    }

    func loadNotes() throws -> [MemoryNote] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([MemoryNote].self, from: data)
    }

    func saveNotes(_ notes: [MemoryNote]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(notes)
        try data.write(to: fileURL, options: [.atomic])
    }
}

struct MemorySearchIndex {
    static func search(
        query: String,
        notes: [MemoryNote],
        scope: MemoryNoteScope,
        limit: Int
    ) -> [MemoryNote] {
        let tokens = tokenize(query)
        guard !tokens.isEmpty else { return [] }

        let ranked = notes
            .filter { $0.scope == scope }
            .map { note in
                let searchable = tokenize(note.title + " " + note.content)
                let overlap = tokens.intersection(searchable).count
                return (note, overlap)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.createdAt > rhs.0.createdAt
                }
                return lhs.1 > rhs.1
            }

        return ranked.prefix(limit).map(\.0)
    }

    private static func tokenize(_ value: String) -> Set<String> {
        let parts = value
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
        return Set(parts)
    }
}
