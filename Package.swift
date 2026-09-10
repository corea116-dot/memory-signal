// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemoryPressure",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MemoryPressure", targets: ["MemoryPressure"])],
    targets: [.executableTarget(name: "MemoryPressure", path: "Sources")]
)
