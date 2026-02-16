import Foundation
import SQLite3

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct Conversation: Sendable, Equatable {
    public let id: String
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum ConversationMessageRole: String, Sendable, Equatable {
    case system
    case user
    case assistant
}

public struct ConversationMessage: Sendable, Equatable {
    public let id: String
    public let conversationID: String
    public let role: ConversationMessageRole
    public let content: String
    public let createdAt: Date

    public init(
        id: String,
        conversationID: String,
        role: ConversationMessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public protocol ConversationStoring: Sendable {
    func createConversation(title: String) async throws -> Conversation
    func listConversations() async throws -> [Conversation]
    func fetchConversation(id: String) async throws -> Conversation?
    func renameConversation(id: String, title: String) async throws
    func deleteConversation(id: String) async throws
    func addMessage(conversationID: String, role: ConversationMessageRole, content: String) async throws -> ConversationMessage
    func listMessages(conversationID: String) async throws -> [ConversationMessage]
}

public enum ConversationStoreError: Error, Sendable, Equatable {
    case invalidDatabasePath
    case openDatabase(String)
    case execute(String)
    case prepare(String)
    case step(String)
    case invalidMessageRole(String)
}

public actor InMemoryConversationStore: ConversationStoring {
    private var conversations: [Conversation] = []
    private var messagesByConversationID: [String: [ConversationMessage]] = [:]

    public init() {}

    public func createConversation(title: String) async throws -> Conversation {
        let now = Date()
        let conversation = Conversation(
            id: UUID().uuidString,
            title: normalizedTitle(title),
            createdAt: now,
            updatedAt: now
        )
        conversations.append(conversation)
        sortConversationsByUpdatedAt()
        return conversation
    }

    public func listConversations() async throws -> [Conversation] {
        sortConversationsByUpdatedAt()
        return conversations
    }

    public func fetchConversation(id: String) async throws -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    public func renameConversation(id: String, title: String) async throws {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let current = conversations[index]
        conversations[index] = Conversation(
            id: current.id,
            title: normalizedTitle(title),
            createdAt: current.createdAt,
            updatedAt: Date()
        )
        sortConversationsByUpdatedAt()
    }

    public func deleteConversation(id: String) async throws {
        conversations.removeAll(where: { $0.id == id })
        messagesByConversationID[id] = nil
    }

    public func addMessage(
        conversationID: String,
        role: ConversationMessageRole,
        content: String
    ) async throws -> ConversationMessage {
        let message = ConversationMessage(
            id: UUID().uuidString,
            conversationID: conversationID,
            role: role,
            content: content,
            createdAt: Date()
        )

        var messages = messagesByConversationID[conversationID] ?? []
        messages.append(message)
        messagesByConversationID[conversationID] = messages
        touchConversation(id: conversationID)

        return message
    }

    public func listMessages(conversationID: String) async throws -> [ConversationMessage] {
        messagesByConversationID[conversationID] ?? []
    }

    private func normalizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Conversation" : trimmed
    }

    private func touchConversation(id: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let current = conversations[index]
        conversations[index] = Conversation(
            id: current.id,
            title: current.title,
            createdAt: current.createdAt,
            updatedAt: Date()
        )
        sortConversationsByUpdatedAt()
    }

    private func sortConversationsByUpdatedAt() {
        conversations.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

public final class SQLiteConversationStore: @unchecked Sendable, ConversationStoring {
    private let db: OpaquePointer

    public init(databaseURL: URL) throws {
        guard databaseURL.isFileURL else {
            throw ConversationStoreError.invalidDatabasePath
        }

        let parentDirectory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard openResult == SQLITE_OK, let openedHandle = handle else {
            let message = Self.errorMessage(for: handle)
            if let handle {
                sqlite3_close(handle)
            }
            throw ConversationStoreError.openDatabase(message)
        }

        db = openedHandle
        try Self.execute(
            on: db,
            """
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
            ON messages(conversation_id, created_at);
            """
        )
    }

    deinit {
        sqlite3_close(db)
    }

    public static func defaultStore(appName: String = "Bzzbe") throws -> SQLiteConversationStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = (base ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent(appName, isDirectory: true)
        let databaseURL = root.appendingPathComponent("conversations.sqlite3", isDirectory: false)
        return try SQLiteConversationStore(databaseURL: databaseURL)
    }

    public func createConversation(title: String) async throws -> Conversation {
        let now = Date()
        let conversation = Conversation(
            id: UUID().uuidString,
            title: normalizedTitle(title),
            createdAt: now,
            updatedAt: now
        )

        let statement = try prepare(
            """
            INSERT INTO conversations (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, conversation.id, -1, sqliteTransientDestructor)
        sqlite3_bind_text(statement, 2, conversation.title, -1, sqliteTransientDestructor)
        sqlite3_bind_double(statement, 3, conversation.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 4, conversation.updatedAt.timeIntervalSince1970)

        try stepExpectingDone(statement)
        return conversation
    }

    public func listConversations() async throws -> [Conversation] {
        let statement = try prepare(
            """
            SELECT id, title, created_at, updated_at
            FROM conversations
            ORDER BY updated_at DESC, created_at DESC;
            """
        )
        defer { sqlite3_finalize(statement) }

        var result: [Conversation] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                result.append(conversation(from: statement))
            case SQLITE_DONE:
                return result
            default:
                throw ConversationStoreError.step(Self.errorMessage(for: db))
            }
        }
    }

    public func fetchConversation(id: String) async throws -> Conversation? {
        let statement = try prepare(
            """
            SELECT id, title, created_at, updated_at
            FROM conversations
            WHERE id = ?
            LIMIT 1;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, sqliteTransientDestructor)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return conversation(from: statement)
        case SQLITE_DONE:
            return nil
        default:
            throw ConversationStoreError.step(Self.errorMessage(for: db))
        }
    }

    public func renameConversation(id: String, title: String) async throws {
        let statement = try prepare(
            """
            UPDATE conversations
            SET title = ?, updated_at = ?
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, normalizedTitle(title), -1, sqliteTransientDestructor)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, id, -1, sqliteTransientDestructor)

        try stepExpectingDone(statement)
    }

    public func deleteConversation(id: String) async throws {
        let statement = try prepare(
            """
            DELETE FROM conversations
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, sqliteTransientDestructor)
        try stepExpectingDone(statement)
    }

    public func addMessage(
        conversationID: String,
        role: ConversationMessageRole,
        content: String
    ) async throws -> ConversationMessage {
        let now = Date()
        let message = ConversationMessage(
            id: UUID().uuidString,
            conversationID: conversationID,
            role: role,
            content: content,
            createdAt: now
        )

        let insertStatement = try prepare(
            """
            INSERT INTO messages (id, conversation_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?);
            """
        )
        defer { sqlite3_finalize(insertStatement) }

        sqlite3_bind_text(insertStatement, 1, message.id, -1, sqliteTransientDestructor)
        sqlite3_bind_text(insertStatement, 2, message.conversationID, -1, sqliteTransientDestructor)
        sqlite3_bind_text(insertStatement, 3, message.role.rawValue, -1, sqliteTransientDestructor)
        sqlite3_bind_text(insertStatement, 4, message.content, -1, sqliteTransientDestructor)
        sqlite3_bind_double(insertStatement, 5, message.createdAt.timeIntervalSince1970)

        try stepExpectingDone(insertStatement)
        try updateConversationTimestamp(conversationID: conversationID, at: now)

        return message
    }

    public func listMessages(conversationID: String) async throws -> [ConversationMessage] {
        let statement = try prepare(
            """
            SELECT id, conversation_id, role, content, created_at
            FROM messages
            WHERE conversation_id = ?
            ORDER BY created_at ASC, rowid ASC;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, conversationID, -1, sqliteTransientDestructor)

        var result: [ConversationMessage] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                result.append(try message(from: statement))
            case SQLITE_DONE:
                return result
            default:
                throw ConversationStoreError.step(Self.errorMessage(for: db))
            }
        }
    }

    private func updateConversationTimestamp(conversationID: String, at date: Date) throws {
        let statement = try prepare(
            """
            UPDATE conversations
            SET updated_at = ?
            WHERE id = ?;
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, conversationID, -1, sqliteTransientDestructor)
        try stepExpectingDone(statement)
    }

    private func normalizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "New Conversation" : trimmed
    }

    private func execute(_ sql: String) throws {
        try Self.execute(on: db, sql)
    }

    private static func execute(on db: OpaquePointer, _ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.execute(errorMessage(for: db))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw ConversationStoreError.prepare(Self.errorMessage(for: db))
        }
        return statement
    }

    private func stepExpectingDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationStoreError.step(Self.errorMessage(for: db))
        }
    }

    private func conversation(from statement: OpaquePointer) -> Conversation {
        let id = String(cString: sqlite3_column_text(statement, 0))
        let title = String(cString: sqlite3_column_text(statement, 1))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
        return Conversation(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt)
    }

    private func message(from statement: OpaquePointer) throws -> ConversationMessage {
        let id = String(cString: sqlite3_column_text(statement, 0))
        let conversationID = String(cString: sqlite3_column_text(statement, 1))
        let rawRole = String(cString: sqlite3_column_text(statement, 2))
        let content = String(cString: sqlite3_column_text(statement, 3))
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))

        guard let role = ConversationMessageRole(rawValue: rawRole) else {
            throw ConversationStoreError.invalidMessageRole(rawRole)
        }

        return ConversationMessage(
            id: id,
            conversationID: conversationID,
            role: role,
            content: content,
            createdAt: createdAt
        )
    }

    private static func errorMessage(for handle: OpaquePointer?) -> String {
        guard let handle else { return "Unknown SQLite error" }
        guard let cMessage = sqlite3_errmsg(handle) else { return "Unknown SQLite error" }
        return String(cString: cMessage)
    }
}
