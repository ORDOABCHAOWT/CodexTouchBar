// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexTouchBar",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "CodexTouchBarCore", targets: ["CodexTouchBarCore"]),
        .executable(name: "CodexTouchBar", targets: ["CodexTouchBar"]),
        .executable(name: "CodexTouchBarCoreChecks", targets: ["CodexTouchBarCoreChecks"]),
    ],
    targets: [
        .target(
            name: "CodexTouchBarCore",
            path: "Sources/CodexTouchBarCore"
        ),
        .target(
            name: "TouchBarPrivateBridge",
            path: "Sources/TouchBarPrivateBridge",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "CodexTouchBar",
            dependencies: ["CodexTouchBarCore", "TouchBarPrivateBridge"],
            path: "Sources/CodexTouchBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .executableTarget(
            name: "CodexTouchBarCoreChecks",
            dependencies: ["CodexTouchBarCore"],
            path: "Sources/CodexTouchBarCoreChecks"
        ),
    ]
)
