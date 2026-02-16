import CryptoKit
import Foundation

public enum ArtifactHashAlgorithm: String, Sendable, Equatable {
    case sha256
}

public struct ArtifactChecksum: Sendable, Equatable {
    public let algorithm: ArtifactHashAlgorithm
    public let value: String

    public init(algorithm: ArtifactHashAlgorithm = .sha256, value: String) throws {
        let normalized = try ArtifactVerifier.normalizeSHA256Hex(value)
        self.algorithm = algorithm
        self.value = normalized
    }
}

public enum ArtifactVerificationError: Error, Sendable, Equatable {
    case unsupportedAlgorithm(ArtifactHashAlgorithm)
    case sourceNotFound(URL)
    case invalidChecksumFormat(String)
    case checksumMismatch(expected: String, actual: String)
}

extension ArtifactVerificationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedAlgorithm(algorithm):
            return "Verification failed: unsupported algorithm \(algorithm.rawValue)."
        case let .sourceNotFound(url):
            return "Verification failed: downloaded artifact not found at \(url.path)."
        case let .invalidChecksumFormat(value):
            return "Verification failed: invalid checksum format '\(value)'. Expected a 64-character SHA-256 hex string."
        case let .checksumMismatch(expected, actual):
            return "Verification failed: checksum mismatch. Expected \(expected), got \(actual). Retry download or contact support if it persists."
        }
    }
}

public protocol ArtifactVerifying: Sendable {
    func checksum(for fileURL: URL, algorithm: ArtifactHashAlgorithm) throws -> String
    func verify(fileURL: URL, against checksum: ArtifactChecksum) throws
}

public struct ArtifactVerifier: ArtifactVerifying {
    public init() {}

    public func checksum(for fileURL: URL, algorithm: ArtifactHashAlgorithm = .sha256) throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ArtifactVerificationError.sourceNotFound(fileURL)
        }

        switch algorithm {
        case .sha256:
            return try sha256(for: fileURL)
        }
    }

    public func verify(fileURL: URL, against checksum: ArtifactChecksum) throws {
        let actual = try self.checksum(for: fileURL, algorithm: checksum.algorithm)
        if actual != checksum.value {
            throw ArtifactVerificationError.checksumMismatch(expected: checksum.value, actual: actual)
        }
    }

    private func sha256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func normalizeSHA256Hex(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^[0-9a-f]{64}$"
        let range = normalized.range(of: pattern, options: .regularExpression)
        guard range != nil else {
            throw ArtifactVerificationError.invalidChecksumFormat(value)
        }
        return normalized
    }
}
