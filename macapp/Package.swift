// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FakeGPS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "FakeGPS",
            path: "Sources/FakeGPS"
        )
    ]
)
