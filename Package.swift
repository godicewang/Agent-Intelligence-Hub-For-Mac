// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "FrostADR",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "FrostADR", targets: ["FrostADR"])
  ],
  targets: [
    .executableTarget(
      name: "FrostADR",
      path: "Sources/FrostADR",
      resources: [
        .process("Discovery/Fingerprints")
      ]
    )
  ]
)
