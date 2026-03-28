// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FanControlMVP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "fancontrol-mvp",
            targets: ["FanControlMVP"]
        )
    ],
    targets: [
        .target(
            name: "CSMCBridge",
            path: "src/CSMCBridge",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "FanControlMVP",
            dependencies: ["CSMCBridge"],
            path: "src/FanControlMVP",
            resources: [
                .copy("Resources/IOKitSensors.xml")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        )
    ]
)
