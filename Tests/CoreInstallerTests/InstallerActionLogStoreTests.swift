import CoreInstaller
import Foundation
import Testing

@Test("JSONInstallerActionLogStore appends entries and returns them newest-first")
func actionLogStoreAppendAndList() throws {
    let store = JSONInstallerActionLogStore(fileURL: makeTemporaryActionLogURL())

    let first = InstallerActionLogEntry(
        timestamp: Date(timeIntervalSince1970: 1_000),
        category: "install.started",
        message: "Install started"
    )
    let second = InstallerActionLogEntry(
        timestamp: Date(timeIntervalSince1970: 2_000),
        category: "install.completed",
        message: "Install completed"
    )

    try store.append(first)
    try store.append(second)

    let allEntries = try store.listEntries(limit: nil)
    #expect(allEntries.map(\.category) == ["install.completed", "install.started"])

    let limited = try store.listEntries(limit: 1)
    #expect(limited.count == 1)
    #expect(limited.first?.category == "install.completed")
}

@Test("JSONInstallerActionLogStore exports readable text log")
func actionLogStoreExportText() throws {
    let store = JSONInstallerActionLogStore(fileURL: makeTemporaryActionLogURL())
    try store.append(
        InstallerActionLogEntry(
            timestamp: Date(timeIntervalSince1970: 3_000),
            category: "verification.passed",
            message: "Checksum verified"
        )
    )

    let export = try store.exportText(limit: nil)
    #expect(export.contains("verification.passed"))
    #expect(export.contains("Checksum verified"))
}

private func makeTemporaryActionLogURL() -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-tests", isDirectory: true)
    let filename = "installer-action-log-\(UUID().uuidString).json"
    return root.appendingPathComponent(filename, isDirectory: false)
}
