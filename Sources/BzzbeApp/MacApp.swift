#if canImport(SwiftUI)
import CoreHardware
import SwiftUI

@main
struct BzzbeMacApp: App {
    @AppStorage("hasCompletedInitialSetup") private var hasCompletedInitialSetup = false

    private let gate = PlatformGate()
    private let capabilityProfile = DefaultHardwareProfiler().currentProfile()

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
