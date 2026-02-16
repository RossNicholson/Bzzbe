#if canImport(SwiftUI)
import SwiftUI
import CoreHardware

struct UnsupportedMacView: View {
    let architecture: MachineArchitecture
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unsupported Mac")
                .font(.largeTitle.bold())

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Detected architecture: \(architecture.rawValue)")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()

            Text("To use Bzzbe, install on an Apple Silicon Mac (M1, M2, M3, or newer).")
                .font(.body)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
