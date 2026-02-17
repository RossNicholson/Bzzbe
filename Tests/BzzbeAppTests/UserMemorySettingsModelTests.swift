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
