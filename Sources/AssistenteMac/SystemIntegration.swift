import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Avvio automatico all'accensione (Impostazioni di Sistema → Generali →
/// Elementi login). Funziona solo nell'app vera (bundle .app).
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        get { isAvailable && SMAppService.mainApp.status == .enabled }
        set {
            guard isAvailable else { return }
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                // Se macOS rifiuta (es. app non nella cartella Applicazioni), l'interruttore
                // mostrerà semplicemente lo stato reale.
            }
        }
    }
}

/// Scorciatoia da tastiera globale (⌥Spazio) per aprire l'assistente da
/// qualunque app. Usa la registrazione classica dei tasti rapidi di macOS:
/// NON serve il permesso di Accessibilità e non legge gli altri tasti.
final class GlobalHotKey {
    /// La scorciatoia, per mostrarla all'utente.
    static let label = "⌥Spazio"

    // Il gestore di eventi è una funzione C: niente contesto, quindi
    // l'azione sta in una variabile statica (c'è una sola scorciatoia).
    nonisolated(unsafe) private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    /// `nil` se la combinazione è già usata da un'altra app.
    init?(action: @escaping () -> Void) {
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4153_5349), id: 1)  // "ASSI"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
