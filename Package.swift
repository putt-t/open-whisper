// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenWhisperApp",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "open-whisper", targets: ["OpenWhisperApp"]),
    ],
    targets: [
        .executableTarget(
            name: "OpenWhisperApp",
            path: "Sources/OpenWhisperApp"
        ),
    ]
)
