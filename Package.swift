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
        // Logica condivisa: raccolta dati di sistema, AI, funzioni.
        // Non dipende da SwiftUI, così è testabile e riusabile.
        // Languages/: un pacchetto JSON per lingua (testi, parole chiave, guide).
        .target(name: "AssistenteCore", resources: [.copy("Languages")]),

        // App nella barra dei menu (solo interfaccia).
        .executableTarget(name: "AssistenteMac", dependencies: ["AssistenteCore"]),

        // Piccolo strumento da terminale per sviluppatori: prova le funzioni
        // senza dover aprire l'interfaccia.
        .executableTarget(name: "assistente-cli", dependencies: ["AssistenteCore"]),

        .testTarget(name: "AssistenteCoreTests", dependencies: ["AssistenteCore"]),
    ]
)
