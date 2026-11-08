import AssistenteCore
import AppKit
import SwiftUI

@main
struct AssistenteMacApp: App {
    private let model = AssistantViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        model.appDidLaunch()
        DemoScreenshots.runIfRequested()
        DemoGIF.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
        } label: {
            Image(systemName: model.alerts.active.isEmpty ? "questionmark.bubble" : "exclamationmark.bubble.fill")
                .accessibilityLabel(model.alerts.active.isEmpty ? "Mac Assistant" : L.t("ui.menubar.alert.a11y"))
        }
        .menuBarExtraStyle(.window)
    }
}
