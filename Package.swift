// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "embyExternalUrl-Manager",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "EmbyExternalUrlManager",
            path: "Sources/EmbyExternalUrlManager",
            exclude: [
                "Resources/AppIcon.icns"
            ],
            resources: [
                .copy("Resources/Templates")
            ]
        )
    ]
)
