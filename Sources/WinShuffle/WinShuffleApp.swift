import SwiftUI

@main
struct WinShuffleApp: App {
    @NSApplicationDelegateAdaptor(WinShuffleAppDelegate.self) private var appDelegate
    @StateObject private var settings: ShuffleSettings
    @StateObject private var coordinator: WindowShuffleCoordinator
    @StateObject private var runtime: AppRuntimeController

    init() {
        let settings = ShuffleSettings()
        let coordinator = WindowShuffleCoordinator(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _coordinator = StateObject(wrappedValue: coordinator)
        _runtime = StateObject(wrappedValue: AppRuntimeController(coordinator: coordinator, settings: settings))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .frame(minWidth: 420, minHeight: 420)
                .task {
                    runtime.activate()
                }
                .onChange(of: settings.hotKey) { _, _ in
                    runtime.updateHotKey()
                }
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesView()
                .environmentObject(settings)
        }

        MenuBarExtra("WinShuffle", systemImage: "rectangle.3.group.bubble") {
            MenuBarContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .task {
                    runtime.activate()
                }
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

private struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var coordinator: WindowShuffleCoordinator
    @EnvironmentObject private var settings: ShuffleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WinShuffle")
                .font(.headline)

            Text(coordinator.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("Shuffle Windows") {
                coordinator.shuffle()
            }
            .disabled(!coordinator.hasAccessibilityAccess || coordinator.isAnimating)

            Button("Refresh Windows") {
                coordinator.refreshWindows()
            }

            Button("Open Main Window") {
                openWindow(id: "main")
            }

            SettingsLink {
                Text("Preferences")
            }

            Divider()

            HStack {
                Text("Hotkey")
                Spacer()
                Text(settings.hotKeyLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Divider()

            Button("Quit WinShuffle") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
