public enum MachineArchitecture: String, Sendable {
    case arm64
    case x86_64
    case unknown

    public var isAppleSiliconCompatible: Bool {
        self == .arm64
    }

    public static var current: MachineArchitecture {
        #if arch(arm64)
        return .arm64
        #elseif arch(x86_64)
        return .x86_64
        #else
        return .unknown
        #endif
    }
}
