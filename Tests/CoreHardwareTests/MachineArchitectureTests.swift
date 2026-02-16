import CoreHardware
import Testing

@Test
func arm64IsMarkedSupported() {
    #expect(MachineArchitecture.arm64.isAppleSiliconCompatible)
}

@Test
func x86AndUnknownAreMarkedUnsupported() {
    #expect(!MachineArchitecture.x86_64.isAppleSiliconCompatible)
    #expect(!MachineArchitecture.unknown.isAppleSiliconCompatible)
}
