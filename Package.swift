// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSwap",
    platforms: [.macOS(.v13)],
    targets: [
        // The status snapshot, its wording and the helper commands. No UI.
        .target(name: "SwapCore"),
        // The menu bar app.
        .executableTarget(name: "ClaudeSwap", dependencies: ["SwapCore"]),
        .testTarget(name: "SwapCoreTests", dependencies: ["SwapCore"]),
    ]
)
