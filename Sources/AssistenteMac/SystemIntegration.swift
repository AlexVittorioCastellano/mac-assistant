import AppKit
import Carbon.HIToolbox
import ServiceManagement

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
            }
        }
    }
}

final class GlobalHotKey {
    static let label = "⌥Spazio"

    nonisolated(unsafe) private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init?(action: @escaping () -> Void) {
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x4153_5349), id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }
}
