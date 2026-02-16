#if canImport(SwiftUI)
import CoreHardware
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct BzzbeMacApp: App {
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    private let gate = PlatformGate()
    private let capabilityProfile = DefaultHardwareProfiler().currentProfile()

    init() {
#if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
#endif
    }

    var body: some Scene {
        WindowGroup {
            if gate.isSupported {
                if hasCompletedInitialSetup {
                    AppShellView()
                } else {
                    InstallerOnboardingView(profile: capabilityProfile) {
                        hasCompletedInitialSetup = true
                    }
                }
            } else {
                UnsupportedMacView(
                    architecture: gate.architecture,
                    message: gate.unsupportedReason
                )
            }
        }
    }
}
#endif
