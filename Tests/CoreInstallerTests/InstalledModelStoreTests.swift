import CoreInstaller
import Foundation
import Testing

@Test("JSONInstalledModelStore persists and reloads installed model metadata")
func savesAndLoadsRecord() throws {
    let fileURL = try makeTemporaryDirectory()
        .appendingPathComponent("installed-model.json", isDirectory: false)
    let store = JSONInstalledModelStore(fileURL: fileURL)

    let record = InstalledModelRecord(
        modelID: "qwen2.5:7b-instruct-q4_K_M",
        tier: "balanced",
        artifactPath: "/tmp/qwen.artifact",
        checksumSHA256: String(repeating: "a", count: 64),
        version: "1",
        installedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try store.save(record: record)
    let reloaded = try store.load()
    #expect(reloaded == record)
}

@Test("JSONInstalledModelStore returns nil when metadata is absent")
func returnsNilWhenMetadataMissing() throws {
    let fileURL = try makeTemporaryDirectory()
        .appendingPathComponent("installed-model.json", isDirectory: false)
    let store = JSONInstalledModelStore(fileURL: fileURL)

    let value = try store.loadIfAvailable()
    #expect(value == nil)
}

@Test("JSONInstalledModelStore clears saved metadata")
func clearsMetadata() throws {
    let fileURL = try makeTemporaryDirectory()
        .appendingPathComponent("installed-model.json", isDirectory: false)
    let store = JSONInstalledModelStore(fileURL: fileURL)

    let record = InstalledModelRecord(
        modelID: "llama3.2:3b-instruct-q4_K_M",
        tier: "small",
        artifactPath: "/tmp/llama.artifact",
        checksumSHA256: String(repeating: "b", count: 64),
        version: "1"
    )

    try store.save(record: record)
    try store.clear()
    #expect(try store.loadIfAvailable() == nil)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-model-store-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
