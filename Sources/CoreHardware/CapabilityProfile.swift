import Foundation

public struct CapabilityProfile: Sendable, Equatable {
    public let architecture: String
    public let memoryGB: Int
    public let freeDiskGB: Int
    public let performanceCores: Int

    public init(
        architecture: String,
        memoryGB: Int,
        freeDiskGB: Int,
        performanceCores: Int
    ) {
        self.architecture = architecture
        self.memoryGB = max(0, memoryGB)
        self.freeDiskGB = max(0, freeDiskGB)
        self.performanceCores = max(0, performanceCores)
    }
}

public protocol HardwareProfiling {
    func currentProfile() -> CapabilityProfile
}

public struct DefaultHardwareProfiler: HardwareProfiling {
    public init() {}

    public func currentProfile() -> CapabilityProfile {
        CapabilityProfile(
            architecture: MachineArchitecture.current.rawValue,
            memoryGB: Self.bytesToGigabytes(ProcessInfo.processInfo.physicalMemory),
            freeDiskGB: Self.freeDiskGigabytes(),
            performanceCores: max(1, ProcessInfo.processInfo.activeProcessorCount)
        )
    }

    public static func bytesToGigabytes(_ bytes: UInt64) -> Int {
        Int(bytes / 1_073_741_824)
    }

    public static func freeDiskGigabytes(path: String = NSHomeDirectory()) -> Int {
        do {
            let values = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = values[.systemFreeSize] as? NSNumber {
                return bytesToGigabytes(freeSize.uint64Value)
            }
        } catch {
            return 0
        }

        return 0
    }
}
