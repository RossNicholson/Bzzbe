import CoreHardware
import Testing

@Test
func defaultHardwareProfilerReturnsProfileWithNonNegativeValues() {
    let profile = DefaultHardwareProfiler().currentProfile()

    #expect(profile.architecture == MachineArchitecture.current.rawValue)
    #expect(profile.memoryGB >= 0)
    #expect(profile.freeDiskGB >= 0)
    #expect(profile.performanceCores >= 1)
}

@Test
func bytesToGigabytesUsesBinaryBase() {
    #expect(DefaultHardwareProfiler.bytesToGigabytes(1_073_741_824) == 1)
    #expect(DefaultHardwareProfiler.bytesToGigabytes(2_147_483_648) == 2)
}

@Test
func capabilityProfileNormalizesNegativeInputsToZero() {
    let profile = CapabilityProfile(
        architecture: "test",
        memoryGB: -1,
        freeDiskGB: -20,
        performanceCores: -4
    )

    #expect(profile.memoryGB == 0)
    #expect(profile.freeDiskGB == 0)
    #expect(profile.performanceCores == 0)
}
