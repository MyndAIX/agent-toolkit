// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceHotkey",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "VoiceHotkey",
            dependencies: [],
            path: "Sources"
        )
    ]
)
