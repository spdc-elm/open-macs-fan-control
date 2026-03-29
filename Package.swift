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
            name: "fan-control-cli",
            targets: ["FanControlCLI"]
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
            name: "FanControlCLI",
            dependencies: ["FanControlRuntime"],
            path: "src/FanControlCLI"
        ),
        .testTarget(
            name: "FanControlRuntimeTests",
            dependencies: ["FanControlRuntime"],
            path: "Tests/FanControlRuntimeTests"
        )
    ]
)
