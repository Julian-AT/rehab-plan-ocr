// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RehaCore",
    platforms: [.iOS("26.0")],
    products: [.library(name: "RehaCore", targets: ["RehaCore"])],
    targets: [
        .binaryTarget(name: "RehaCoreFFI", path: "RehaCoreFFI.xcframework"),
        .target(name: "RehaCore", dependencies: ["RehaCoreFFI"], linkerSettings: [
            .linkedLibrary("c++"), .linkedLibrary("sqlite3"),
            .linkedFramework("Accelerate"), .linkedFramework("CoreML"),
            .linkedFramework("Foundation"), .linkedFramework("Security")
        ])
    ], swiftLanguageModes: [.v6]
)
