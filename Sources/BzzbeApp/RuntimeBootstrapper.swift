import CoreInstaller
import Foundation

struct RuntimeBootstrapConfiguration: Sendable, Equatable {
    let runtimeBaseURL: URL
    let runtimeHealthPath: String
    let runtimeDownloadURL: URL
    let runtimeArchiveFileName: String
    let reachabilityTimeoutSeconds: TimeInterval
    let reachabilityPollIntervalSeconds: TimeInterval

    init(
        runtimeBaseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        runtimeHealthPath: String = "/api/tags",
        runtimeDownloadURL: URL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!,
        runtimeArchiveFileName: String = "Ollama-darwin.zip",
        reachabilityTimeoutSeconds: TimeInterval = 2,
        reachabilityPollIntervalSeconds: TimeInterval = 1
    ) {
        self.runtimeBaseURL = runtimeBaseURL
        self.runtimeHealthPath = runtimeHealthPath
        self.runtimeDownloadURL = runtimeDownloadURL
        self.runtimeArchiveFileName = runtimeArchiveFileName
        self.reachabilityTimeoutSeconds = max(1, reachabilityTimeoutSeconds)
        self.reachabilityPollIntervalSeconds = max(0.25, reachabilityPollIntervalSeconds)
    }
}

enum RuntimeBootstrapError: Error, Equatable {
    case runtimeAppNotInstalled
    case runtimeArchiveExtractionFailed(String)
    case runtimeAppMissingInArchive
    case runtimeUnavailableAfterStart
}

extension RuntimeBootstrapError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .runtimeAppNotInstalled:
            return "Local runtime is not installed yet."
        case let .runtimeArchiveExtractionFailed(details):
            return "Failed to extract runtime archive. \(details)"
        case .runtimeAppMissingInArchive:
            return "Downloaded runtime archive did not include the runtime app bundle."
        case .runtimeUnavailableAfterStart:
            return "Runtime did not become reachable after startup. If prompted, choose 'Move to Applications' and open Ollama."
        }
    }
}

protocol RuntimeBootstrapping: Sendable {
    func isRuntimeReachable() async -> Bool
    func startRuntimeIfInstalled() async -> Bool
    func restartRuntimeIfInstalled() async -> Bool
    func installAndStartRuntime() async throws
}

extension RuntimeBootstrapping {
    func restartRuntimeIfInstalled() async -> Bool {
        await startRuntimeIfInstalled()
    }
}

actor OllamaRuntimeBootstrapper: RuntimeBootstrapping {
    private let configuration: RuntimeBootstrapConfiguration
    private let artifactDownloader: ArtifactDownloading
    private let fileManager: FileManager
    private let urlSession: URLSession
    private var runtimeServeProcess: Process?

    init(
        configuration: RuntimeBootstrapConfiguration = .init(),
        artifactDownloader: ArtifactDownloading = ResumableArtifactDownloadManager(),
        fileManager: FileManager = .default,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.artifactDownloader = artifactDownloader
        self.fileManager = fileManager
        self.urlSession = urlSession
    }

    func isRuntimeReachable() async -> Bool {
        var request = URLRequest(url: healthURL())
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.reachabilityTimeoutSeconds

        do {
            let (_, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    func startRuntimeIfInstalled() async -> Bool {
        if await isRuntimeReachable() {
            return true
        }

        guard let appURL = installedRuntimeAppURL() else {
            return false
        }

        do {
            try launchRuntime(at: appURL)
            return await waitForRuntimeReachable(timeoutSeconds: 20)
        } catch {
            return false
        }
    }

    func restartRuntimeIfInstalled() async -> Bool {
        terminateKnownRuntimeProcesses()
        return await startRuntimeIfInstalled()
    }

    func installAndStartRuntime() async throws {
        let archiveURL = try await downloadRuntimeArchive()
        let extractedRoot = try extractRuntimeArchive(at: archiveURL)
        let extractedAppURL = try runtimeAppURL(in: extractedRoot)
        let installedAppURL = try installRuntimeApp(from: extractedAppURL)
        try launchRuntime(at: installedAppURL)

        let reachable = await waitForRuntimeReachable(timeoutSeconds: 30)
        guard reachable else {
            throw RuntimeBootstrapError.runtimeUnavailableAfterStart
        }
    }

    private func healthURL() -> URL {
        configuration.runtimeBaseURL.appending(path: trimmedLeadingSlash(configuration.runtimeHealthPath))
    }

    private func runtimeRootURL() -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Bzzbe", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
    }

    private func runtimeArchiveURL() -> URL {
        runtimeRootURL().appendingPathComponent(configuration.runtimeArchiveFileName, isDirectory: false)
    }

    private func runtimeExtractedDirectoryURL() -> URL {
        runtimeRootURL().appendingPathComponent("extracted", isDirectory: true)
    }

    private func installedRuntimeAppURL() -> URL? {
        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Ollama.app", isDirectory: true)
        if fileManager.fileExists(atPath: userApplications.path) {
            return userApplications
        }

        let systemApplications = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent("Ollama.app", isDirectory: true)
        if fileManager.fileExists(atPath: systemApplications.path) {
            return systemApplications
        }

        return nil
    }

    private func downloadRuntimeArchive() async throws -> URL {
        let root = runtimeRootURL()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let archiveURL = runtimeArchiveURL()
        let downloadID = "runtime.bootstrap.archive"
        let request = ArtifactDownloadRequest(
            id: downloadID,
            sourceURL: configuration.runtimeDownloadURL,
            destinationURL: archiveURL
        )

        var completedURL: URL?
        let stream = artifactDownloader.startDownload(request)
        for try await event in stream {
            if case let .completed(destinationURL, _) = event {
                completedURL = destinationURL
            }
        }

        guard let completedURL else {
            throw RuntimeBootstrapError.runtimeArchiveExtractionFailed("Archive download ended unexpectedly.")
        }
        return completedURL
    }

    private func extractRuntimeArchive(at archiveURL: URL) throws -> URL {
        let extractedDirectoryURL = runtimeExtractedDirectoryURL()
        if fileManager.fileExists(atPath: extractedDirectoryURL.path) {
            try fileManager.removeItem(at: extractedDirectoryURL)
        }
        try fileManager.createDirectory(at: extractedDirectoryURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", archiveURL.path, "-d", extractedDirectoryURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let outputText = String(data: outputData, encoding: .utf8) ?? "unknown unzip error"
            throw RuntimeBootstrapError.runtimeArchiveExtractionFailed(outputText)
        }

        return extractedDirectoryURL
    }

    private func runtimeAppURL(in extractedRoot: URL) throws -> URL {
        let directCandidate = extractedRoot.appendingPathComponent("Ollama.app", isDirectory: true)
        if fileManager.fileExists(atPath: directCandidate.path) {
            return directCandidate
        }

        if let enumerator = fileManager.enumerator(at: extractedRoot, includingPropertiesForKeys: nil) {
            for case let candidate as URL in enumerator {
                if candidate.lastPathComponent == "Ollama.app" {
                    return candidate
                }
            }
        }

        throw RuntimeBootstrapError.runtimeAppMissingInArchive
    }

    private func installRuntimeApp(from extractedAppURL: URL) throws -> URL {
        let destinationDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationAppURL = destinationDirectory.appendingPathComponent("Ollama.app", isDirectory: true)
        if fileManager.fileExists(atPath: destinationAppURL.path) {
            try fileManager.removeItem(at: destinationAppURL)
        }
        try fileManager.copyItem(at: extractedAppURL, to: destinationAppURL)
        return destinationAppURL
    }

    private func launchRuntime(at appURL: URL) throws {
        if let runtimeServeProcess {
            if runtimeServeProcess.isRunning {
                return
            }
            self.runtimeServeProcess = nil
        }

        if let runtimeExecutableURL = runtimeServeExecutableURL(for: appURL),
           let serveProcess = try launchServeProcess(executableURL: runtimeExecutableURL) {
            runtimeServeProcess = serveProcess
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-j", appURL.path]
        try process.run()
        process.waitUntilExit()
    }

    private func terminateKnownRuntimeProcesses() {
        if let runtimeServeProcess, runtimeServeProcess.isRunning {
            runtimeServeProcess.terminate()
            runtimeServeProcess.waitUntilExit()
        }
        runtimeServeProcess = nil

        runBestEffortProcess(
            executablePath: "/usr/bin/pkill",
            arguments: ["-f", "Ollama.app/.*/ollama serve"]
        )
        runBestEffortProcess(
            executablePath: "/usr/bin/pkill",
            arguments: ["-x", "ollama"]
        )
        runBestEffortProcess(
            executablePath: "/usr/bin/pkill",
            arguments: ["-x", "Ollama"]
        )

        Thread.sleep(forTimeInterval: 0.35)
    }

    private func runBestEffortProcess(executablePath: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    private func runtimeServeExecutableURL(for appURL: URL) -> URL? {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let candidates = [
            contentsURL
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent("ollama", isDirectory: false),
            contentsURL
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("ollama", isDirectory: false)
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func launchServeProcess(executableURL: URL) throws -> Process? {
        let serveProcess = Process()
        serveProcess.executableURL = executableURL
        serveProcess.arguments = ["serve"]
        serveProcess.standardOutput = Pipe()
        serveProcess.standardError = Pipe()
        try serveProcess.run()

        Thread.sleep(forTimeInterval: 0.3)
        guard serveProcess.isRunning else {
            return nil
        }

        serveProcess.terminationHandler = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.clearRuntimeServeProcessIfMatches(serveProcess)
            }
        }
        return serveProcess
    }

    private func clearRuntimeServeProcessIfMatches(_ process: Process) {
        if runtimeServeProcess === process {
            runtimeServeProcess = nil
        }
    }

    private func waitForRuntimeReachable(timeoutSeconds: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let timeout = Duration.seconds(timeoutSeconds)
        let deadline = clock.now.advanced(by: timeout)
        var pollIntervalSeconds = max(configuration.reachabilityPollIntervalSeconds, 0.25)
        let maxPollIntervalSeconds = max(2.0, configuration.reachabilityPollIntervalSeconds * 4)

        while clock.now < deadline {
            if await isRuntimeReachable() {
                return true
            }

            try? await Task.sleep(for: .milliseconds(Int(pollIntervalSeconds * 1_000)))
            pollIntervalSeconds = min(maxPollIntervalSeconds, pollIntervalSeconds * 1.5)
        }

        return await isRuntimeReachable()
    }

    private func trimmedLeadingSlash(_ value: String) -> String {
        if value.hasPrefix("/") {
            return String(value.dropFirst())
        }
        return value
    }
}
