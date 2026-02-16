#if canImport(SwiftUI)
import CoreHardware
import SwiftUI

@main
struct BzzbeMacApp: App {
    private let gate = PlatformGate()

    var body: some Scene {
        WindowGroup {
            if gate.isSupported {
                AppShellView()
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
