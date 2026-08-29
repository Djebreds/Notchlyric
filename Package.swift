// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchLyricsCore", targets: ["NotchLyricsCore"]),
        .executable(name: "NotchLyricsApp", targets: ["NotchLyricsApp"]),
    ],
    targets: [
        .target(name: "NotchLyricsCore"),
        .executableTarget(name: "NotchLyricsApp", dependencies: ["NotchLyricsCore"]),
        .testTarget(name: "NotchLyricsCoreTests", dependencies: ["NotchLyricsCore"]),
    ]
)
