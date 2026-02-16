import CoreInstaller
import Foundation
import Testing

@Test("ArtifactVerifier computes SHA-256 checksum")
func computesSHA256Checksum() throws {
    let directory = try makeTemporaryDirectory()
    let artifactURL = directory.appendingPathComponent("artifact.txt")
    try Data("abc".utf8).write(to: artifactURL, options: .atomic)

    let verifier = ArtifactVerifier()
    let checksum = try verifier.checksum(for: artifactURL, algorithm: .sha256)

    #expect(checksum == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test("ArtifactVerifier rejects mismatched checksum")
func rejectsMismatchedChecksum() throws {
    let directory = try makeTemporaryDirectory()
    let artifactURL = directory.appendingPathComponent("artifact.bin")
    try Data("payload".utf8).write(to: artifactURL, options: .atomic)

    let verifier = ArtifactVerifier()
    let checksum = try ArtifactChecksum(value: String(repeating: "0", count: 64))

    #expect(throws: ArtifactVerificationError.checksumMismatch(expected: checksum.value, actual: try verifier.checksum(for: artifactURL, algorithm: .sha256))) {
        try verifier.verify(fileURL: artifactURL, against: checksum)
    }
}

@Test("ArtifactChecksum normalizes uppercase SHA-256 input")
func normalizesChecksumInput() throws {
    let checksum = try ArtifactChecksum(value: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD")
    #expect(checksum.value == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test("ArtifactChecksum validates SHA-256 format")
func validatesChecksumFormat() {
    #expect(throws: ArtifactVerificationError.invalidChecksumFormat("not-a-checksum")) {
        _ = try ArtifactChecksum(value: "not-a-checksum")
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bzzbe-verifier-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
