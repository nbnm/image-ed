// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Still", targets: ["Still"])],
    targets: [
        .executableTarget(name: "Still", path: "Sources/Still")
    ],
    swiftLanguageModes: [.v5]
)
