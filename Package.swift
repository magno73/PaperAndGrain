// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PaperAndGrain",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PaperAndGrain", targets: ["PaperAndGrain"])],
    targets: [.executableTarget(name: "PaperAndGrain")]
)
