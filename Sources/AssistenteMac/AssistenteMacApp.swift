import AssistenteCore
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
        model.appDidLaunch()
        DemoScreenshots.runIfRequested()  // solo per sviluppatori (immagini del README)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            // Con un avviso attivo l'icona cambia: si capisce senza aprire nulla.
            Image(systemName: model.alerts.active.isEmpty ? "questionmark.bubble" : "exclamationmark.bubble.fill")
                .accessibilityLabel(model.alerts.active.isEmpty ? "Mac Assistant" : L.t("ui.menubar.alert.a11y"))
        }
        .menuBarExtraStyle(.window)
    }
}
