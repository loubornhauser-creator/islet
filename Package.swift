// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CMultitouch", path: "Sources/CMultitouch"),
        .executableTarget(
            name: "Islet",
            dependencies: ["CMultitouch"],
            path: "Sources/Islet",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMediaIO"),
            ]
        ),
    ]
)
