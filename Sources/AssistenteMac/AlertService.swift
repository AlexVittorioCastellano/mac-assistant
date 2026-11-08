import AssistenteCore
import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class AlertService {
    private(set) var active: [MacAlert] = []

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { requestPermission() } else { active = [] }
        }
    }

    private static let enabledKey = "avvisiAutomatici"
    private var monitor = AlertMonitor()
    private let system = SystemMonitor()
    private var loop: Task<Void, Never>?
    private let interval: Duration
    private let notificationDelegate = NotificationDelegate()

    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true

        if ProcessInfo.processInfo.environment["ASSISTENTE_AVVISI_RAPIDI"] != nil {
            var rules = AlertMonitor.Rules()
            rules.cpuDuration = 10
            rules.memoryDuration = 10
            rules.heatDuration = 10
            monitor = AlertMonitor(rules: rules)
            interval = .seconds(5)
        } else {
            interval = .seconds(60)
        }
    }

    func start() {
        guard loop == nil else { return }
        if canNotify {
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
        if enabled { requestPermission() }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: self?.interval ?? .seconds(60))
            }
        }
    }

    private func tick() async {
        guard enabled, let snapshot = try? await system.snapshot() else { return }
        let disk = DiskMonitor.volumeCapacity()
        let fresh = monitor.update(snapshot: snapshot, diskFree: disk.free, diskTotal: disk.total)
        active = monitor.active
        for alert in fresh { notify(alert) }
    }

    private func requestPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ alert: MacAlert) {
        guard canNotify else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: alert.id + "-\(Date().timeIntervalSince1970)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
