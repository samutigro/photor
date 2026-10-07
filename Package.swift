// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Photor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Photor", targets: ["PhotorApp"])],
    dependencies: [.package(path: "Packages/PhotorKit")],
    targets: [
        .executableTarget(name: "PhotorApp", dependencies: [
            .product(name: "PhotorCore", package: "PhotorKit"),
            .product(name: "PhotorDecoders", package: "PhotorKit"),
            .product(name: "PhotorRendering", package: "PhotorKit")
        ], path: "App")
    ]
)
