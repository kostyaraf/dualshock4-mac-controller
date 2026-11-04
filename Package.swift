// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DS4Mouse",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ds4mouse",
            path: "Sources/DS4Mouse",
            linkerSettings: [
                .linkedFramework("GameController"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreHaptics"),
            ]
        ),
    ]
)
