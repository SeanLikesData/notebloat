// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Notebloat",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Notebloat",
            path: "Sources/Notebloat"
        )
    ]
)
