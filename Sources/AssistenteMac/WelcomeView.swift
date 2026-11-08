import AppKit
import SwiftUI

/// Benvenuto al primo avvio: tre pagine brevi (cosa fa, dove trovarla,
/// preferenze). Si può rivedere dal menu delle impostazioni.
struct WelcomeView: View {
    let alerts: AlertService
    let hotKeyWorks: Bool
    let onDone: () -> Void

    // Stato della pagina nel view model del benvenuto (niente @State: in
    // macOS 27 è una macro che richiede Xcode).
    @Bindable var state: WelcomeState

    var body: some View {
        VStack(spacing: 18) {
            Group {
                switch state.page {
                case 0: page1
                case 1: page2
                default: page3
                }
            }
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .top)

            HStack {
                // Puntini di avanzamento
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == state.page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if state.page > 0 {
                    Button("Indietro") { state.page -= 1 }
                }
                Button(state.page < 2 ? "Avanti" : "Inizia") {
                    if state.page < 2 { state.page += 1 } else { onDone() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    private var page1: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Ciao! Sono il tuo assistente per il Mac")
                .font(.title2.weight(.semibold))
            Text("Fammi domande in italiano sul tuo Mac: perché è lento, cos'è un processo, dove è finito lo spazio, come si fa qualcosa. Posso anche controllarlo in un clic, spiegarti un messaggio strano e avvisarti se qualcosa non va.")
                .fixedSize(horizontal: false, vertical: true)
            Label("Tutto resta sul tuo Mac: niente dati inviati, niente pubblicità, niente account.",
                  systemImage: "lock.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var page2: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Dove trovarmi")
                .font(.title2.weight(.semibold))
            Label("Clicca l'icona con il fumetto in alto a destra, nella barra dei menu.", systemImage: "questionmark.bubble")
                .fixedSize(horizontal: false, vertical: true)
            if hotKeyWorks {
                Label("Oppure premi \(GlobalHotKey.label) da qualunque app.", systemImage: "keyboard")
            }
            Label("Puoi anche parlare: premi il microfono accanto al campo di testo.", systemImage: "mic")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var page3: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("Due preferenze")
                .font(.title2.weight(.semibold))
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 })) {
                VStack(alignment: .leading) {
                    Text("Apri all'accensione del Mac")
                    Text("Così gli avvisi funzionano sempre.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!LaunchAtLogin.isAvailable)
            Toggle(isOn: Binding(get: { alerts.enabled }, set: { alerts.enabled = $0 })) {
                VStack(alignment: .leading) {
                    Text("Avvisami se qualcosa non va")
                    Text("macOS ti chiederà il permesso per le notifiche.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Puoi cambiarle quando vuoi dall'ingranaggio in basso nel riquadro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .toggleStyle(.switch)
    }
}

@MainActor
@Observable
final class WelcomeState {
    var page = 0
    /// Scelta dell'utente: applicata solo quando preme «Inizia», non prima.
    var launchAtLogin: Bool
    init(launchAtLogin: Bool) { self.launchAtLogin = launchAtLogin }
}

/// Mostra il benvenuto in una finestra normale (al primo avvio o su richiesta).
@MainActor
final class WelcomeWindow {
    private static let shownKey = "benvenutoMostrato"
    private var window: NSWindow?

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    func show(alerts: AlertService, hotKeyWorks: Bool) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        // Al primo avvio proponiamo l'avvio automatico già acceso (ma lo
        // applichiamo solo quando l'utente preme «Inizia»).
        let state = WelcomeState(launchAtLogin: Self.wasShown ? LaunchAtLogin.isEnabled : LaunchAtLogin.isAvailable)
        let view = WelcomeView(alerts: alerts, hotKeyWorks: hotKeyWorks, onDone: { [weak self] in
            if LaunchAtLogin.isEnabled != state.launchAtLogin { LaunchAtLogin.isEnabled = state.launchAtLogin }
            self?.close()
        }, state: state)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Benvenuto in Assistente Mac"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        // Un'app della barra dei menu non "ruba" il primo piano da sola: la
        // finestra di benvenuto deve comunque vedersi sopra le altre.
        window.level = .floating
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
        UserDefaults.standard.set(true, forKey: Self.shownKey)
    }

    private func close() {
        window?.close()
        window = nil
    }
}
