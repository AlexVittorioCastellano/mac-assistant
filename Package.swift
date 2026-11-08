// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AssistenteMac",
    defaultLocalization: "it",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "AssistenteMac", targets: ["AssistenteMac"]),
        .executable(name: "assistente-cli", targets: ["assistente-cli"]),
    ],
    targets: [

        .target(name: "AssistenteCore", resources: [.copy("Languages")]),

        .executableTarget(name: "AssistenteMac", dependencies: ["AssistenteCore"]),

        .executableTarget(name: "assistente-cli", dependencies: ["AssistenteCore"]),

        .testTarget(name: "AssistenteCoreTests", dependencies: ["AssistenteCore"]),
    ]
)
