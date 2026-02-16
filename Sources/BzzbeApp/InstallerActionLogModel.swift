import Combine
import CoreInstaller
import Foundation

@MainActor
final class InstallerActionLogModel: ObservableObject {
    @Published private(set) var entries: [InstallerActionLogEntry] = []
    @Published private(set) var exportStatusMessage: String?
    @Published private(set) var errorMessage: String?

    private let actionLogStore: InstallerActionLogging
    private let fileManager: FileManager

    init(
        actionLogStore: InstallerActionLogging = JSONInstallerActionLogStore.defaultStore(),
        fileManager: FileManager = .default
    ) {
        self.actionLogStore = actionLogStore
        self.fileManager = fileManager
    }

    func refresh(limit: Int = 100) {
        do {
            entries = try actionLogStore.listEntries(limit: limit)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load action log. \(error.localizedDescription)"
        }
    }

    func exportToDownloads(limit: Int = 1_000) {
        do {
            let content = try actionLogStore.exportText(limit: limit)
            let destinationURL = try exportDestinationURL()
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
            exportStatusMessage = "Exported action log to \(destinationURL.path)"
            errorMessage = nil
        } catch {
            errorMessage = "Failed to export action log. \(error.localizedDescription)"
        }
    }

    private func exportDestinationURL() throws -> URL {
        let base = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let timestamp = Self.exportTimestampFormatter.string(from: Date())
        return base.appendingPathComponent("bzzbe-installer-action-log-\(timestamp).txt", isDirectory: false)
    }

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
