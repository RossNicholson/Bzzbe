import CoreHardware

struct PlatformGate {
    let architecture: MachineArchitecture

    init(architecture: MachineArchitecture = .current) {
        self.architecture = architecture
    }

    var isSupported: Bool {
        architecture.isAppleSiliconCompatible
    }

    var unsupportedReason: String {
        switch architecture {
        case .x86_64:
            return "Bzzbe currently supports Apple Silicon Macs only."
        case .unknown:
            return "Bzzbe could not verify this Mac architecture and cannot continue."
        case .arm64:
            return ""
        }
    }
}
