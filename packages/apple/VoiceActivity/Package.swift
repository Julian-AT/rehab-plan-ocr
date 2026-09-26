// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "VoiceActivity", products: [.library(name: "CFvad", targets: ["CFvad"])],
  targets: [
    .target(
      name: "CFvad", exclude: ["src/Makefile.am", "src/CMakeLists.txt"],
      publicHeadersPath: "include", cSettings: [.headerSearchPath("src")])
  ])
