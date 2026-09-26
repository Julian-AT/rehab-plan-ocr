// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "tauri-plugin-reha-calendar",
    platforms: [.iOS(.v17)],
    products: [.library(name: "tauri-plugin-reha-calendar", type: .static, targets: ["tauri-plugin-reha-calendar"])],
    dependencies: [.package(name: "Tauri", path: "../.tauri/tauri-api"), .package(path: "../../../packages/apple/AppleServices")],
    targets: [.target(name: "tauri-plugin-reha-calendar", dependencies: [.byName(name: "Tauri"), .product(name: "AppleServices", package: "AppleServices")], path: "Sources")]
)
