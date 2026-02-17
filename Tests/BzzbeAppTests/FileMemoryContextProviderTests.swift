@testable import BzzbeApp
import Foundation
import Testing

@Test("FileMemoryContextProvider merges base memory with scoped dated notes")
func fileMemoryContextProviderMergesScopedNotes() throws {
    let suiteName = "BzzbeAppTests.MemoryProvider.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create UserDefaults suite")
        return
    }
    defaults.removePersistentDomain(forName: suiteName)
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let appSupportURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("BzzbeAppTests-MemoryProvider-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: appSupportURL)
    }

    defaults.set(true, forKey: UserMemoryConfiguration.enabledKey)
    defaults.set(MemoryNoteScope.shared.rawValue, forKey: UserMemoryConfiguration.scopeKey)

    let memoryFileURL = UserMemoryConfiguration.memoryFileURL(appSupportDirectoryURL: appSupportURL)
    try FileManager.default.createDirectory(
        at: memoryFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "Base memory line".write(to: memoryFileURL, atomically: true, encoding: .utf8)

    let notesStore = JSONMemoryNotesStore.defaultStore(appSupportDirectoryURL: appSupportURL)
    try notesStore.saveNotes(
        [
            MemoryNote(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_000),
                scope: .private,
                title: "Private note",
                content: "Do not include this in shared context."
            ),
            MemoryNote(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 2_000),
                scope: .shared,
                title: "Shared note",
                content: "Include this for shared context."
            )
        ]
    )

    let provider = FileMemoryContextProvider(
        defaults: defaults,
        fileManager: .default,
        appSupportDirectoryURL: appSupportURL
    )

    let context = provider.loadContext()
    let results = provider.searchNotes(query: "shared include", scope: .shared, limit: 5)

    #expect(context.isEnabled == true)
    #expect(context.scope == .shared)
    #expect(context.content.contains("Base memory line"))
    #expect(context.content.contains("Shared note"))
    #expect(!context.content.contains("Private note"))
    #expect(results.count == 1)
    #expect(results.first?.title == "Shared note")
}
