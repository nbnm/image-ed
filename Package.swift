// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Image-Eddie",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Image-Eddie", targets: ["ImageEddie"])],
    targets: [
        .executableTarget(name: "ImageEddie", path: "Sources/ImageEddie")
    ],
    swiftLanguageModes: [.v5]
)
