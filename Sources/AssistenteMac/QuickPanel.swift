import AppKit
import SwiftUI

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

        panel.makeKeyAndOrderFront(nil)
    }

    private func make(model: AssistantViewModel) -> Panel {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

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

        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let host = NSHostingView(rootView: ContentView(model: model)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top))
        host.sizingOptions = []
        panel.contentView = host

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { panel.center(); return }
        let x = screen.midX - panel.frame.width / 2
        let y = screen.maxY - panel.frame.height - screen.height * 0.08
        panel.setFrameOrigin(NSPoint(x: x, y: max(screen.minY, y)))
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    }
}
