// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AppleServices",
  platforms: [.iOS(.v17)],
  products: [.library(name: "AppleServices", targets: ["AppleServices"])],
  targets: [.target(name: "AppleServices")],
  swiftLanguageModes: [.v6]
)
