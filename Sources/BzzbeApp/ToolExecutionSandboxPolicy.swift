import CoreAgents
import Foundation

struct ToolExecutionSandboxRequest: Equatable {
    let filePaths: [String]
    let networkHosts: [String]
    let requestsHostNetwork: Bool
    let requestsPrivilegeEscalation: Bool
    let mountPaths: [String]

    static func fromPromptInput(_ input: String) -> ToolExecutionSandboxRequest {
        let absolutePathPattern = #"(?:^|\s)(/[^\s,;]+)"#
        let urlPattern = #"https?://[^\s]+"#
        let mountPattern = #"(?i)(?:--mount(?:=|\s+)|mount:)\s*([^\s,;]+)"#
        let absolutePaths = captures(matching: absolutePathPattern, in: input)
        let urls = captures(matching: urlPattern, in: input, captureGroup: 0)
        let hosts = urls.compactMap { URL(string: $0)?.host?.lowercased() }
        let mounts = captures(matching: mountPattern, in: input)
        let lowercased = input.lowercased()

        return ToolExecutionSandboxRequest(
            filePaths: absolutePaths,
            networkHosts: hosts,
            requestsHostNetwork: lowercased.contains("--network host") || lowercased.contains("host network"),
            requestsPrivilegeEscalation: lowercased.contains("sudo ") || lowercased.contains(" as root") || lowercased.contains("--privileged"),
            mountPaths: mounts
        )
    }

    private static func captures(
        matching pattern: String,
        in input: String,
        captureGroup: Int = 1
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { match in
            guard
                match.numberOfRanges > captureGroup,
                let captureRange = Range(match.range(at: captureGroup), in: input)
            else {
                return nil
            }
            return String(input[captureRange])
        }
    }
}

enum ToolExecutionSandboxViolation: Equatable {
    case disallowedPath(String)
    case disallowedNetworkHost(String)
    case hostNetworkDenied
    case privilegeEscalationDenied
    case disallowedMount(String)

    var message: String {
        switch self {
        case let .disallowedPath(path):
            return "Path is outside allowed roots: \(path)"
        case let .disallowedNetworkHost(host):
            return "Network host is not allowed: \(host)"
        case .hostNetworkDenied:
            return "Host networking is disabled by sandbox policy."
        case .privilegeEscalationDenied:
            return "Privilege escalation is disabled by sandbox policy."
        case let .disallowedMount(mount):
            return "Mount path is blocked by sandbox policy: \(mount)"
        }
    }
}

struct ToolExecutionSandboxConfiguration {
    let allowedPathPrefixes: [String]
    let allowedNetworkHosts: Set<String>
    let allowHostNetwork: Bool
    let allowPrivilegeEscalation: Bool
    let blockedMountPrefixes: [String]

    init(
        allowedPathPrefixes: [String] = [NSHomeDirectory(), NSTemporaryDirectory()],
        allowedNetworkHosts: Set<String> = [],
        allowHostNetwork: Bool = false,
        allowPrivilegeEscalation: Bool = false,
        blockedMountPrefixes: [String] = ["/", "/System", "/Library", "/private", "/Volumes"]
    ) {
        self.allowedPathPrefixes = allowedPathPrefixes
        self.allowedNetworkHosts = allowedNetworkHosts
        self.allowHostNetwork = allowHostNetwork
        self.allowPrivilegeEscalation = allowPrivilegeEscalation
        self.blockedMountPrefixes = blockedMountPrefixes
    }
}

struct ToolExecutionSandboxEvaluation: Equatable {
    let violations: [ToolExecutionSandboxViolation]
    let remediationHints: [String]
    let configurationDiagnostics: [String]

    var isAllowed: Bool {
        violations.isEmpty
    }

    var summary: String {
        if isAllowed {
            return "Sandbox checks passed."
        }
        return "Sandbox blocked request: \(violations.map(\.message).joined(separator: " | "))"
    }

    var userSummary: String {
        if isAllowed {
            return "Safety checks passed."
        }
        return "Sandbox blocked request. Some requested actions are outside the allowed safety settings."
    }
}

struct ToolExecutionSandboxPolicy {
    private let configuration: ToolExecutionSandboxConfiguration

    init(configuration: ToolExecutionSandboxConfiguration = ToolExecutionSandboxConfiguration()) {
        self.configuration = configuration
    }

    func evaluate(
        request: ToolExecutionSandboxRequest,
        requiredProfile: AgentToolAccessLevel
    ) -> ToolExecutionSandboxEvaluation {
        guard requiredProfile.rank >= AgentToolAccessLevel.localFiles.rank else {
            return ToolExecutionSandboxEvaluation(
                violations: [],
                remediationHints: [],
                configurationDiagnostics: diagnostics()
            )
        }

        var violations: [ToolExecutionSandboxViolation] = []

        for path in request.filePaths where !isAllowed(path: path) {
            violations.append(.disallowedPath(path))
        }
        for host in request.networkHosts where !isAllowed(host: host) {
            violations.append(.disallowedNetworkHost(host))
        }
        if request.requestsHostNetwork && !configuration.allowHostNetwork {
            violations.append(.hostNetworkDenied)
        }
        if request.requestsPrivilegeEscalation && !configuration.allowPrivilegeEscalation {
            violations.append(.privilegeEscalationDenied)
        }
        for mount in request.mountPaths where isBlockedMount(mount) {
            violations.append(.disallowedMount(mount))
        }

        let dedupedViolations = deduplicate(violations)
        return ToolExecutionSandboxEvaluation(
            violations: dedupedViolations,
            remediationHints: remediationHints(for: dedupedViolations),
            configurationDiagnostics: diagnostics()
        )
    }

    func diagnostics() -> [String] {
        var issues: [String] = []
        if configuration.allowedPathPrefixes.isEmpty {
            issues.append("No allowed path prefixes configured.")
        }
        for prefix in configuration.allowedPathPrefixes where !prefix.hasPrefix("/") {
            issues.append("Allowed path prefix must be absolute: \(prefix)")
        }
        if configuration.allowHostNetwork && configuration.allowedNetworkHosts.isEmpty {
            issues.append("Host networking is enabled with no explicit network host allowlist.")
        }
        return issues
    }

    private func isAllowed(path: String) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return configuration.allowedPathPrefixes.contains(where: { prefix in
            let standardizedPrefix = URL(fileURLWithPath: prefix).standardizedFileURL.path
            return standardizedPath == standardizedPrefix || standardizedPath.hasPrefix(standardizedPrefix + "/")
        })
    }

    private func isAllowed(host: String) -> Bool {
        configuration.allowedNetworkHosts.contains(host)
    }

    private func isBlockedMount(_ mount: String) -> Bool {
        let normalized = mount.lowercased()
        return configuration.blockedMountPrefixes.contains(where: { blockedPrefix in
            let blocked = blockedPrefix.lowercased()
            return normalized == blocked || normalized.hasPrefix(blocked + "/")
        })
    }

    private func deduplicate(_ violations: [ToolExecutionSandboxViolation]) -> [ToolExecutionSandboxViolation] {
        var seen: Set<String> = []
        var deduped: [ToolExecutionSandboxViolation] = []
        for violation in violations {
            let key = violation.message
            if seen.insert(key).inserted {
                deduped.append(violation)
            }
        }
        return deduped
    }

    private func remediationHints(for violations: [ToolExecutionSandboxViolation]) -> [String] {
        var hints: [String] = []
        let allowedPaths = configuration.allowedPathPrefixes
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .sorted()
        let allowedHosts = configuration.allowedNetworkHosts.sorted()

        for violation in violations {
            let hint: String
            switch violation {
            case .disallowedPath:
                if allowedPaths.isEmpty {
                    hint = "No safe file roots are configured. Add allowed file paths in app settings."
                } else {
                    hint = "Use file paths under: \(allowedPaths.joined(separator: ", "))."
                }
            case .disallowedNetworkHost:
                if allowedHosts.isEmpty {
                    hint = "Remove external URLs from this task, or allow required hosts in settings."
                } else {
                    hint = "Use only allowed network hosts: \(allowedHosts.joined(separator: ", "))."
                }
            case .hostNetworkDenied:
                hint = "Remove host-network requests (for example '--network host')."
            case .privilegeEscalationDenied:
                hint = "Remove privilege escalation steps (for example 'sudo', 'as root', or '--privileged')."
            case .disallowedMount:
                hint = "Avoid restricted mount targets and use project/local paths instead."
            }
            if !hints.contains(hint) {
                hints.append(hint)
            }
        }

        return hints
    }
}
