import AppKit
import Foundation

@MainActor
final class AppRuntimeController: ObservableObject {
    private let coordinator: WindowShuffleCoordinator
    private let settings: ShuffleSettings
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private var hasActivated = false

    init(coordinator: WindowShuffleCoordinator, settings: ShuffleSettings) {
        self.coordinator = coordinator
        self.settings = settings
    }

    func activate() {
        guard !hasActivated else {
            return
        }

        hasActivated = true
        coordinator.startMonitoring()
        installHotKey()
    }

    func updateHotKey() {
        guard hasActivated else {
            return
        }

        installHotKey()
    }

    private func installHotKey() {
        hotKeyMonitor.install(hotKey: settings.hotKey) { [coordinator] in
            coordinator.shuffle()
        }
    }
}

final class WinShuffleAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
