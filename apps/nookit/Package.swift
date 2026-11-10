// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nookit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Nookit", targets: ["Nookit"])
    ],
    targets: [
        .executableTarget(
            name: "Nookit",
            path: "Sources/Nookit",
            resources: [
                .process("Resources")
            ]
        )
    ],
    // Swift 6 language mode is strict about actor isolation in AppKit bridges.
    // The app is being brought up pragmatically; tightening happens after the UI lands.
    //
    // NOTE: use `swiftLanguageModes` (not the deprecated `swiftLanguageVersions`).
    // The Swift 6.0.3 Command Line Tools on this Mac ship a PackageDescription
    // dylib that only exports the `SwiftLanguageMode` overload; referring to the
    // deprecated `SwiftVersion` initialiser fails at manifest link time.
    swiftLanguageModes: [.v5]
)
