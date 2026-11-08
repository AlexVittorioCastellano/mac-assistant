import AppKit
import SwiftUI

@main
struct AssistenteMacApp: App {
    // L'istanza di `App` vive quanto l'app, quindi basta una costante.
    // (Non usiamo @State: in macOS 27 è una macro disponibile solo con Xcode,
    // e vogliamo che il progetto compili anche con i soli Command Line Tools.)
    private let model = AssistantViewModel()

    init() {
        // Niente icona nel Dock, anche quando si avvia con `swift run`.
        // (Il bundle .app lo indica anche con LSUIElement nell'Info.plist.)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Assistente Mac", systemImage: "questionmark.bubble") {
            ContentView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
