import CoreInference
import Foundation
import Darwin

@main
enum BzzbePerfHarnessMain {
    static func main() async {
        do {
            let config = try HarnessConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
            try await runBenchmark(configuration: config)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

private struct HarnessConfiguration {
    enum ClientKind: String {
        case runtime
        case mock
    }

    let clientKind: ClientKind
    let baseURL: URL
    let modelIdentifier: String
    let modelDisplayName: String
    let prompt: String
    let runs: Int
    let label: String
    let outputPath: String?

    init(arguments: [String]) throws {
        var clientKind: ClientKind = .runtime
        var baseURL = URL(string: "http://127.0.0.1:11434")!
        var modelIdentifier = "qwen2.5:7b-instruct-q4_K_M"
        var modelDisplayName = "Qwen 2.5 7B Instruct"
        var prompt = "Explain what Bzzbe does in two short sentences."
        var runs = 3
        var label = Host.current().localizedName ?? "Unknown Host"
        var outputPath: String?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--client":
                index += 1
                guard index < arguments.count, let parsed = ClientKind(rawValue: arguments[index]) else {
                    throw HarnessError.invalidArguments("Expected runtime|mock after --client")
                }
                clientKind = parsed
            case "--base-url":
                index += 1
                guard index < arguments.count, let parsed = URL(string: arguments[index]) else {
                    throw HarnessError.invalidArguments("Expected valid URL after --base-url")
                }
                baseURL = parsed
            case "--model":
                index += 1
                guard index < arguments.count else {
                    throw HarnessError.invalidArguments("Expected model identifier after --model")
                }
                modelIdentifier = arguments[index]
                modelDisplayName = modelIdentifier
            case "--prompt":
                index += 1
                guard index < arguments.count else {
                    throw HarnessError.invalidArguments("Expected prompt text after --prompt")
                }
                prompt = arguments[index]
            case "--runs":
                index += 1
                guard index < arguments.count, let parsed = Int(arguments[index]), parsed > 0 else {
                    throw HarnessError.invalidArguments("Expected positive integer after --runs")
                }
                runs = parsed
            case "--label":
                index += 1
                guard index < arguments.count else {
                    throw HarnessError.invalidArguments("Expected machine label after --label")
                }
                label = arguments[index]
            case "--json-out":
                index += 1
                guard index < arguments.count else {
                    throw HarnessError.invalidArguments("Expected file path after --json-out")
                }
                outputPath = arguments[index]
            case "--help":
                printUsageAndExit()
            default:
                throw HarnessError.invalidArguments("Unknown option: \(argument)")
            }
            index += 1
        }

        self.clientKind = clientKind
        self.baseURL = baseURL
        self.modelIdentifier = modelIdentifier
        self.modelDisplayName = modelDisplayName
        self.prompt = prompt
        self.runs = runs
        self.label = label
        self.outputPath = outputPath
    }
}

private struct BenchmarkSample: Codable {
    let run: Int
    let firstTokenLatencyMS: Double
    let totalDurationMS: Double
    let tokenCount: Int
    let tokensPerSecond: Double
    let peakResidentMemoryMB: Double
}

private struct BenchmarkReport: Codable {
    let createdAt: Date
    let clientKind: String
    let label: String
    let model: String
    let baseURL: String
    let prompt: String
    let samples: [BenchmarkSample]
    let averageFirstTokenLatencyMS: Double
    let averageTokensPerSecond: Double
    let peakResidentMemoryMB: Double
}

private enum HarnessError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            return message
        }
    }
}

private func runBenchmark(configuration: HarnessConfiguration) async throws {
    let model = InferenceModelDescriptor(
        identifier: configuration.modelIdentifier,
        displayName: configuration.modelDisplayName,
        contextWindow: 32_768
    )
    let client = makeClient(for: configuration)

    print("Bzzbe Performance Harness")
    print("Client: \(configuration.clientKind.rawValue)")
    print("Label: \(configuration.label)")
    print("Model: \(configuration.modelIdentifier)")
    print("Runs: \(configuration.runs)")
    print("")

    try await client.loadModel(model)

    var samples: [BenchmarkSample] = []
    for runIndex in 1...configuration.runs {
        let sample = try await runSingleBenchmark(
            run: runIndex,
            client: client,
            model: model,
            prompt: configuration.prompt
        )
        samples.append(sample)
        print(
            "run \(sample.run): first-token=\(format(sample.firstTokenLatencyMS))ms | "
                + "tps=\(format(sample.tokensPerSecond)) | "
                + "peak-rss=\(format(sample.peakResidentMemoryMB))MB | "
                + "tokens=\(sample.tokenCount)"
        )
    }

    guard !samples.isEmpty else { return }

    let averageFirstToken = samples.map(\.firstTokenLatencyMS).reduce(0, +) / Double(samples.count)
    let averageTokensPerSecond = samples.map(\.tokensPerSecond).reduce(0, +) / Double(samples.count)
    let peakResidentMemory = samples.map(\.peakResidentMemoryMB).max() ?? 0

    print("")
    print("summary: avg-first-token=\(format(averageFirstToken))ms | avg-tps=\(format(averageTokensPerSecond)) | peak-rss=\(format(peakResidentMemory))MB")

    if let outputPath = configuration.outputPath {
        let report = BenchmarkReport(
            createdAt: Date(),
            clientKind: configuration.clientKind.rawValue,
            label: configuration.label,
            model: configuration.modelIdentifier,
            baseURL: configuration.baseURL.absoluteString,
            prompt: configuration.prompt,
            samples: samples,
            averageFirstTokenLatencyMS: averageFirstToken,
            averageTokensPerSecond: averageTokensPerSecond,
            peakResidentMemoryMB: peakResidentMemory
        )
        try writeReport(report, to: outputPath)
        print("wrote report to \(outputPath)")
    }
}

private func runSingleBenchmark(
    run: Int,
    client: any InferenceClient,
    model: InferenceModelDescriptor,
    prompt: String
) async throws -> BenchmarkSample {
    let request = InferenceRequest(
        model: model,
        messages: [
            InferenceMessage(role: .user, content: prompt)
        ],
        maxOutputTokens: 384,
        temperature: 0.2
    )

    let clock = ContinuousClock()
    let startedAt = clock.now
    let sampler = MemorySampler()
    await sampler.start()

    var firstTokenLatencyMS: Double?
    var tokenCount = 0
    var completedAt = startedAt

    let stream = await client.streamCompletion(request)
    for try await event in stream {
        switch event {
        case .started:
            continue
        case let .token(token):
            if firstTokenLatencyMS == nil {
                firstTokenLatencyMS = milliseconds(from: startedAt, to: clock.now)
            }
            tokenCount += token.split(whereSeparator: \.isWhitespace).count
        case .completed, .cancelled:
            completedAt = clock.now
        }
    }
    completedAt = clock.now

    let peakResidentMemoryBytes = await sampler.stop()
    let totalDurationMS = milliseconds(from: startedAt, to: completedAt)
    let firstToken = firstTokenLatencyMS ?? totalDurationMS
    let generationDurationMS = max(1.0, totalDurationMS - firstToken)
    let tokensPerSecond = Double(tokenCount) / (generationDurationMS / 1_000.0)

    return BenchmarkSample(
        run: run,
        firstTokenLatencyMS: firstToken,
        totalDurationMS: totalDurationMS,
        tokenCount: tokenCount,
        tokensPerSecond: tokensPerSecond,
        peakResidentMemoryMB: Double(peakResidentMemoryBytes) / (1024.0 * 1024.0)
    )
}

private func makeClient(for configuration: HarnessConfiguration) -> any InferenceClient {
    switch configuration.clientKind {
    case .runtime:
        return LocalRuntimeInferenceClient(configuration: LocalRuntimeConfiguration(baseURL: configuration.baseURL))
    case .mock:
        return MockInferenceClient()
    }
}

private actor MemorySampler {
    private var peakResidentBytes: UInt64 = 0
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        peakResidentBytes = currentResidentMemoryBytes()
        task = Task {
            while !Task.isCancelled {
                peakResidentBytes = max(peakResidentBytes, currentResidentMemoryBytes())
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    func stop() -> UInt64 {
        task?.cancel()
        task = nil
        peakResidentBytes = max(peakResidentBytes, currentResidentMemoryBytes())
        return peakResidentBytes
    }
}

private func currentResidentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let status = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundedPointer in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundedPointer, &count)
        }
    }

    guard status == KERN_SUCCESS else { return 0 }
    return UInt64(info.resident_size)
}

private func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: end)
    return Double(duration.components.seconds) * 1_000.0
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000.0
}

private func writeReport(_ report: BenchmarkReport, to outputPath: String) throws {
    let outputURL = URL(fileURLWithPath: outputPath)
    let directory = outputURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try data.write(to: outputURL, options: .atomic)
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func printUsageAndExit() -> Never {
    let usage = """
    Usage:
      swift run BzzbePerfHarness [options]

    Options:
      --client runtime|mock      Inference backend (default: runtime)
      --base-url URL             Runtime base URL (default: http://127.0.0.1:11434)
      --model IDENTIFIER         Model identifier (default: qwen2.5:7b-instruct-q4_K_M)
      --prompt TEXT              Prompt used for measurement
      --runs N                   Number of benchmark runs (default: 3)
      --label NAME               Label for this machine/report row
      --json-out PATH            Optional JSON output path
      --help                     Print this help text
    """
    print(usage)
    exit(0)
}
