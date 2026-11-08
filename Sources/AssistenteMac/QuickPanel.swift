import AppKit
import SwiftUI

/// Pannello flottante aperto con la scorciatoia (⌥Spazio), come Spotlight:
/// stessa interfaccia e stesso stato del riquadro della barra dei menu.
///
/// Perché un pannello separato: il riquadro di `MenuBarExtra` non si può aprire
/// da codice (SwiftUI non lo prevede e i "clic simulati" non funzionano).
@MainActor
final class QuickPanel {
    private var panel: Panel?
    private var resignObserver: NSObjectProtocol?

    func toggle(model: AssistantViewModel) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? make(model: model)
        self.panel = panel
        position(panel)
        // Un pannello "non attivante" riceve la tastiera senza rubare il primo
        // piano all'app che stai usando (come Spotlight).
        panel.makeKeyAndOrderFront(nil)
    }

    private func make(model: AssistantViewModel) -> Panel {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Altezza fissa (il contenuto lungo scorre al suo interno): adattarla al
        // contenuto mentre la risposta arriva crea cicli di layout.
        let height = min(720, screen.height * 0.85)
        let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 400, height: height),
                          styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Solo il pulsante per chiudere: riduci e ingrandisci qui non servono.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let host = NSHostingView(rootView: ContentView(model: model)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top))
        host.sizingOptions = []
        panel.contentView = host

        // Come Spotlight: cliccando altrove il pannello si chiude.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
        return panel
    }

    /// In alto al centro dello schermo, come Spotlight.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { panel.center(); return }
        let x = screen.midX - panel.frame.width / 2
        let y = screen.maxY - panel.frame.height - screen.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: max(screen.minY, y)))
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        /// Esc chiude il pannello.
        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }
}
