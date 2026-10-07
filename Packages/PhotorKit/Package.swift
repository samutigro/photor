// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotorKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhotorCore", targets: ["PhotorCore"]),
        .library(name: "PhotorDecoders", targets: ["PhotorDecoders"]),
        .library(name: "PhotorRendering", targets: ["PhotorRendering"]),
        .executable(name: "PhotorChecks", targets: ["PhotorChecks"])
    ],
    targets: [
        .target(name: "PhotorCore"),
        .target(name: "PhotorDecoders", dependencies: ["PhotorCore"]),
        .target(name: "PhotorRendering", dependencies: ["PhotorCore"], resources: [.copy("PhotoShaders.metal")]),
        .executableTarget(name: "PhotorChecks", dependencies: ["PhotorCore", "PhotorDecoders"], path: "Tests/PhotorCoreTests")
    ]
)
