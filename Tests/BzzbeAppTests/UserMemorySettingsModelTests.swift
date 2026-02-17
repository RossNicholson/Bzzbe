@testable import BzzbeApp
import Foundation
import Testing

@MainActor
@Test("UserMemorySettingsModel defaults to disabled memory and empty content")
func userMemoryDefaults() throws {
    let context = try makeMemoryTestContext()
    defer { context.cleanup() }

    let model = UserMemorySettingsModel(
        defaults: context.defaults,
        fileManager: .default,
        appSupportDirectoryURL: context.appSupportURL
    )

    #expect(model.isMemoryEnabled == false)
    #expect(model.content == "")
    #expect(model.selectedScope == .private)
    #expect(model.notes.isEmpty)
}

@MainActor
@Test("UserMemorySettingsModel persists memory toggle and content")
func userMemoryPersistsToDisk() throws {
    let context = try makeMemoryTestContext()
    defer { context.cleanup() }

    let model = UserMemorySettingsModel(
        defaults: context.defaults,
        fileManager: .default,
        appSupportDirectoryURL: context.appSupportURL
    )

    model.isMemoryEnabled = true
    model.content = "Always answer with concise bullets."
    model.save()

    let restored = UserMemorySettingsModel(
        defaults: context.defaults,
        fileManager: .default,
        appSupportDirectoryURL: context.appSupportURL
    )

    #expect(restored.isMemoryEnabled == true)
    #expect(restored.content == "Always answer with concise bullets.")
}

@MainActor
@Test("UserMemorySettingsModel persists dated notes and scope selection")
func userMemoryPersistsNotesAndScope() throws {
    let context = try makeMemoryTestContext()
    defer { context.cleanup() }

    let model = UserMemorySettingsModel(
        defaults: context.defaults,
        fileManager: .default,
        appSupportDirectoryURL: context.appSupportURL
    )

    model.selectedScope = .shared
    model.noteTitle = "Release preference"
    model.noteScope = .shared
    model.noteContent = "Prefer launch notes in bullet format."
    model.addNote()
    model.noteSearchQuery = "launch bullet"

    #expect(model.notes.count == 1)
    #expect(model.searchResults.count == 1)
    #expect(model.searchResults.first?.scope == .shared)

    let restored = UserMemorySettingsModel(
        defaults: context.defaults,
        fileManager: .default,
        appSupportDirectoryURL: context.appSupportURL
    )

    #expect(restored.selectedScope == .shared)
    #expect(restored.notes.count == 1)
    #expect(restored.notes.first?.title == "Release preference")
    restored.noteSearchQuery = "launch"
    #expect(restored.searchResults.count == 1)
}

private struct MemoryTestContext {
    let defaults: UserDefaults
    let suiteName: String
    let appSupportURL: URL

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: appSupportURL)
    }
}

private func makeMemoryTestContext() throws -> MemoryTestContext {
    let suiteName = "BzzbeAppTests.UserMemory.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Unable to create isolated UserDefaults suite")
    }

    let appSupportURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("BzzbeAppTests-Memory-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

    defaults.removePersistentDomain(forName: suiteName)
    return MemoryTestContext(defaults: defaults, suiteName: suiteName, appSupportURL: appSupportURL)
}
