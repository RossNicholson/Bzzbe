#if canImport(SwiftUI)
@testable import BzzbeApp
import CoreAgents
import Testing

@Test("ToolExecutionSandboxRequest parses risky prompt markers")
func toolExecutionSandboxRequestParsesPromptMarkers() {
    let request = ToolExecutionSandboxRequest.fromPromptInput(
        "Please scan /Users/test/Documents and /tmp/cache. Download from https://example.com with --network host and sudo access --mount /Volumes/Data"
    )

    #expect(request.filePaths.contains("/Users/test/Documents"))
    #expect(request.filePaths.contains("/tmp/cache."))
    #expect(request.networkHosts.contains("example.com"))
    #expect(request.requestsHostNetwork == true)
    #expect(request.requestsPrivilegeEscalation == true)
    #expect(request.mountPaths.contains("/Volumes/Data"))
}

@Test("ToolExecutionSandboxPolicy blocks disallowed paths for risky profiles")
func toolExecutionSandboxPolicyBlocksDisallowedPaths() {
    let policy = ToolExecutionSandboxPolicy(
        configuration: ToolExecutionSandboxConfiguration(
            allowedPathPrefixes: ["/Users/test", "/tmp"],
            allowedNetworkHosts: [],
            allowHostNetwork: false,
            allowPrivilegeEscalation: false,
            blockedMountPrefixes: ["/"]
        )
    )
    let request = ToolExecutionSandboxRequest(
        filePaths: ["/etc/passwd"],
        networkHosts: [],
        requestsHostNetwork: false,
        requestsPrivilegeEscalation: false,
        mountPaths: []
    )

    let evaluation = policy.evaluate(request: request, requiredProfile: .localFiles)

    #expect(evaluation.isAllowed == false)
    #expect(evaluation.violations.contains(.disallowedPath("/etc/passwd")))
}

@Test("ToolExecutionSandboxPolicy bypasses checks for read-only profiles")
func toolExecutionSandboxPolicyBypassesReadOnlyProfiles() {
    let policy = ToolExecutionSandboxPolicy(
        configuration: ToolExecutionSandboxConfiguration(
            allowedPathPrefixes: ["/Users/test"],
            allowedNetworkHosts: [],
            allowHostNetwork: false,
            allowPrivilegeEscalation: false,
            blockedMountPrefixes: ["/"]
        )
    )
    let request = ToolExecutionSandboxRequest(
        filePaths: ["/etc/passwd"],
        networkHosts: ["example.com"],
        requestsHostNetwork: true,
        requestsPrivilegeEscalation: true,
        mountPaths: ["/"]
    )

    let evaluation = policy.evaluate(request: request, requiredProfile: .readOnly)

    #expect(evaluation.isAllowed == true)
    #expect(evaluation.violations.isEmpty)
}

@Test("ToolExecutionSandboxPolicy surfaces configuration diagnostics")
func toolExecutionSandboxPolicySurfacesDiagnostics() {
    let policy = ToolExecutionSandboxPolicy(
        configuration: ToolExecutionSandboxConfiguration(
            allowedPathPrefixes: ["relative/path"],
            allowedNetworkHosts: [],
            allowHostNetwork: true,
            allowPrivilegeEscalation: false,
            blockedMountPrefixes: ["/"]
        )
    )

    let diagnostics = policy.diagnostics()

    #expect(diagnostics.contains(where: { $0.contains("absolute") }))
    #expect(diagnostics.contains(where: { $0.contains("Host networking is enabled") }))
}
#endif
