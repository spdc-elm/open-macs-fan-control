// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacsFanControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "FanControlRuntime",
            targets: ["FanControlRuntime"]
        ),
        .executable(
            name: "root-writer-daemon",
            targets: ["RootWriterDaemon"]
        ),
        .executable(
            name: "fan-control-cli",
            targets: ["FanControlCLI"]
        ),
        .executable(
            name: "fan-control-menu-bar",
            targets: ["FanControlMenuBar"]
        )
    ],
    targets: [
        .target(
            name: "CSMCBridge",
            path: "src/CSMCBridge",
            publicHeadersPath: "."
        ),
        .target(
            name: "FanControlRuntime",
            dependencies: ["CSMCBridge"],
            path: "src/FanControlRuntime",
            resources: [
                .copy("Resources/IOKitSensors.xml")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .executableTarget(
            name: "RootWriterDaemon",
            dependencies: ["FanControlRuntime"],
            path: "src/RootWriterDaemon"
        ),
        .executableTarget(
            name: "FanControlCLI",
            dependencies: ["FanControlRuntime"],
            path: "src/FanControlCLI"
        ),
        .executableTarget(
            name: "FanControlMenuBar",
            dependencies: ["FanControlRuntime"],
            path: "src/FanControlMenuBar"
        ),
        .testTarget(
            name: "FanControlRuntimeTests",
            dependencies: ["FanControlRuntime"],
            path: "Tests/FanControlRuntimeTests"
        )
    ]
)
