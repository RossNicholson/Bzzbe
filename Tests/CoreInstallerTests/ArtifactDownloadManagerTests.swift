import CoreInstaller
import Foundation
import Testing

@Test("ResumableArtifactDownloadManager downloads artifact with progress events")
func downloadsArtifact() async throws {
    let testDirectory = try makeTemporaryDirectory()
    let sourceURL = testDirectory.appendingPathComponent("source.bin")
    let destinationURL = testDirectory.appendingPathComponent("destination.bin")
    try writeSeedFile(to: sourceURL, bytes: 512 * 1024)

    let manager = ResumableArtifactDownloadManager(chunkSize: 32 * 1024)
    let request = ArtifactDownloadRequest(id: "download.full", sourceURL: sourceURL, destinationURL: destinationURL)

    var started = false
    var completed = false
    var previousBytes: Int64 = 0

    let stream = manager.startDownload(request)
    for try await event in stream {
        switch event {
        case let .started(resumedBytes, totalBytes):
            started = true
            #expect(resumedBytes == 0)
            #expect(totalBytes > 0)
        case let .progress(bytesWritten, totalBytes):
            #expect(bytesWritten >= previousBytes)
            #expect(bytesWritten <= totalBytes)
            previousBytes = bytesWritten
        case let .completed(url, totalBytes):
            completed = true
            #expect(url == destinationURL)
            #expect(totalBytes == previousBytes)
        }
    }

    #expect(started)
    #expect(completed)
    #expect(try Data(contentsOf: sourceURL) == Data(contentsOf: destinationURL))
}

@Test("ResumableArtifactDownloadManager resumes from partial file after cancellation")
func resumesFromPartialFile() async throws {
    let testDirectory = try makeTemporaryDirectory()
    let sourceURL = testDirectory.appendingPathComponent("resume-source.bin")
    let destinationURL = testDirectory.appendingPathComponent("resume-destination.bin")
    try writeSeedFile(to: sourceURL, bytes: 2 * 1024 * 1024)

    let manager = ResumableArtifactDownloadManager(chunkSize: 16 * 1024)
    let request = ArtifactDownloadRequest(id: "download.resume", sourceURL: sourceURL, destinationURL: destinationURL)

    var interruptedAt: Int64 = 0
    let firstStream = manager.startDownload(request)
    for try await event in firstStream {
        if case let .progress(bytesWritten, _) = event, bytesWritten > 0 {
            interruptedAt = bytesWritten
            manager.cancelDownload(id: request.id)
            break
        }
    }
    #expect(interruptedAt > 0)

    let secondStream = manager.startDownload(request)
    var resumedFrom: Int64 = 0
    var completed = false
    for try await event in secondStream {
        switch event {
        case let .started(resumedBytes, _):
            resumedFrom = resumedBytes
        case .progress:
            continue
        case .completed:
            completed = true
        }
    }

    #expect(resumedFrom > 0)
    #expect(completed)
    #expect(try Data(contentsOf: sourceURL) == Data(contentsOf: destinationURL))
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-download-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSeedFile(to url: URL, bytes: Int) throws {
    var data = Data(count: bytes)
    data.withUnsafeMutableBytes { rawBuffer in
        guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
        for index in 0..<rawBuffer.count {
            bytes[index] = UInt8(index % 251)
        }
    }
    try data.write(to: url, options: .atomic)
}
