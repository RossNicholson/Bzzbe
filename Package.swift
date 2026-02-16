// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Bzzbe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CoreHardware", targets: ["CoreHardware"]),
        .library(name: "CoreInference", targets: ["CoreInference"]),
        .library(name: "CoreStorage", targets: ["CoreStorage"]),
        .library(name: "CoreInstaller", targets: ["CoreInstaller"]),
        .library(name: "CoreAgents", targets: ["CoreAgents"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .executable(name: "BzzbeApp", targets: ["BzzbeApp"]),
        .executable(name: "BzzbePerfHarness", targets: ["BzzbePerfHarness"])
    ],
    targets: [
        .target(name: "CoreHardware"),
        .target(name: "CoreInference"),
        .target(
            name: "CoreStorage",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(name: "CoreInstaller", dependencies: ["CoreHardware"]),
        .target(name: "CoreAgents"),
        .target(name: "DesignSystem"),
        .executableTarget(
            name: "BzzbePerfHarness",
            dependencies: [
                "CoreInference"
            ]
        ),
        .executableTarget(
            name: "BzzbeApp",
            dependencies: [
                "CoreHardware",
                "CoreInference",
                "CoreStorage",
                "CoreInstaller",
                "CoreAgents",
                "DesignSystem"
            ]
        ),
        .testTarget(name: "CoreHardwareTests", dependencies: ["CoreHardware"]),
        .testTarget(name: "CoreInferenceTests", dependencies: ["CoreInference"]),
        .testTarget(name: "CoreInstallerTests", dependencies: ["CoreInstaller", "CoreHardware"]),
        .testTarget(name: "CoreStorageTests", dependencies: ["CoreStorage"]),
        .testTarget(
            name: "BzzbeAppTests",
            dependencies: [
                "BzzbeApp",
                "CoreInference",
                "CoreStorage"
            ]
        )
    ]
)
