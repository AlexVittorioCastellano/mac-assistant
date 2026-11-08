import AppKit
import AssistenteCore
import SwiftUI

struct WelcomeView: View {
    let alerts: AlertService
    let hotKeyWorks: Bool
    let onDone: () -> Void

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
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle().fill(i == state.page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if state.page > 0 {
                    Button(L.t("ui.welcome.back")) { state.page -= 1 }
                }
                Button(state.page < 2 ? L.t("ui.welcome.next") : L.t("ui.welcome.start")) {
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(L.t("ui.welcome.hello"))
                .font(.title2.weight(.semibold))
            Text(L.t("ui.welcome.what"))
                .fixedSize(horizontal: false, vertical: true)
            Label(L.t("ui.welcome.privacy"),
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
            Text(L.t("ui.welcome.where"))
                .font(.title2.weight(.semibold))
            Label(L.t("ui.welcome.menubar"), systemImage: "questionmark.bubble")
                .fixedSize(horizontal: false, vertical: true)
            if hotKeyWorks {
                Label(L.t("ui.welcome.hotkey", GlobalHotKey.label), systemImage: "keyboard")
            }
            Label(L.t("ui.welcome.voice"), systemImage: "mic")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var page3: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text(L.t("ui.welcome.prefs"))
                .font(.title2.weight(.semibold))
            Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 })) {
                VStack(alignment: .leading) {
                    Text(L.t("ui.welcome.launch"))
                    Text(L.t("ui.welcome.launch.note")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(!LaunchAtLogin.isAvailable)
            Toggle(isOn: Binding(get: { alerts.enabled }, set: { alerts.enabled = $0 })) {
                VStack(alignment: .leading) {
                    Text(L.t("ui.welcome.alerts"))
                    Text(L.t("ui.welcome.alerts.note")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(L.t("ui.welcome.change"))
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

    var launchAtLogin: Bool
    init(launchAtLogin: Bool) { self.launchAtLogin = launchAtLogin }
}

@MainActor
final class WelcomeWindow {
    private static let shownKey = "benvenutoMostrato"
    private var window: NSWindow?

    static var wasShown: Bool { UserDefaults.standard.bool(forKey: shownKey) }

    func show(alerts: AlertService, hotKeyWorks: Bool) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }

        let state = WelcomeState(launchAtLogin: Self.wasShown ? LaunchAtLogin.isEnabled : LaunchAtLogin.isAvailable)
        let view = WelcomeView(alerts: alerts, hotKeyWorks: hotKeyWorks, onDone: { [weak self] in
            if LaunchAtLogin.isEnabled != state.launchAtLogin { LaunchAtLogin.isEnabled = state.launchAtLogin }
            self?.close()
        }, state: state)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = L.t("ui.welcome.title")
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

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
