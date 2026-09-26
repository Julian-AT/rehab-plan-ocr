// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LocalAssistant",
  platforms: [.iOS("26.0"), .macOS("26.0")],
  products: [.library(name: "LocalAssistant", targets: ["LocalAssistant"])],
  targets: [
    .binaryTarget(name: "RehaAssistantNative", path: "RehaAssistantNative.xcframework"),
    .target(
      name: "LocalAssistant", dependencies: ["RehaAssistantNative"],
      linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate")]),
  ], swiftLanguageModes: [.v6]
)
