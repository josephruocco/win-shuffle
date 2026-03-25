// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WinShuffle",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WinShuffle", targets: ["WinShuffle"])
    ],
    targets: [
        .executableTarget(
            name: "WinShuffle",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
