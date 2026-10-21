// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenBar",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "OpenBar",
            path: "Sources/OpenBar",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
