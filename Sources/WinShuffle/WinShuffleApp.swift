import SwiftUI

@main
struct WinShuffleApp: App {
    @StateObject private var settings = ShuffleSettings()
    @StateObject private var coordinator: WindowShuffleCoordinator
    @State private var hotKeyMonitor = GlobalHotKeyMonitor()

    init() {
        let settings = ShuffleSettings()
        _settings = StateObject(wrappedValue: settings)
        _coordinator = StateObject(wrappedValue: WindowShuffleCoordinator(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .frame(minWidth: 420, minHeight: 420)
                .onAppear {
                    coordinator.startMonitoring()
                    hotKeyMonitor.install(hotKey: settings.hotKey) {
                        coordinator.shuffle()
                    }
                }
                .onDisappear {
                    coordinator.stopMonitoring()
                    hotKeyMonitor.uninstall()
                }
                .onChange(of: settings.hotKey) { _, hotKey in
                    hotKeyMonitor.install(hotKey: hotKey) {
                        coordinator.shuffle()
                    }
                }
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView()
                .environmentObject(settings)
        }
    }
}

private struct ContentView: View {
    @EnvironmentObject private var coordinator: WindowShuffleCoordinator
    @EnvironmentObject private var settings: ShuffleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("WinShuffle")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Shuffle open macOS windows like a deck of cards.")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("Global hotkey", systemImage: "keyboard")
                    .font(.subheadline.weight(.semibold))
                Text(settings.hotKeyLabel)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Updated \(coordinator.lastRefresh.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Grant Access") {
                    coordinator.requestAccessibilityAccess()
                }

                SettingsLink {
                    Text("Preferences")
                }

                Button("Refresh") {
                    coordinator.refreshWindows()
                }

                Button("Shuffle Windows") {
                    coordinator.shuffle()
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!coordinator.hasAccessibilityAccess || coordinator.isAnimating)
            }

            Text(coordinator.status)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            if coordinator.windows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No windows loaded")
                        .font(.title3.weight(.semibold))
                    Text("Open a few standard app windows, grant Accessibility access, then wait for auto-refresh or use \(settings.hotKeyLabel).")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(coordinator.windows) { window in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(window.title)
                            .font(.headline)
                        Text(window.appName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
    }
}
