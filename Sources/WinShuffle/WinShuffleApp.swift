import SwiftUI

@main
struct WinShuffleApp: App {
    @StateObject private var coordinator = WindowShuffleCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 420, minHeight: 420)
                .onAppear {
                    coordinator.refreshWindows()
                }
        }
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    @EnvironmentObject private var coordinator: WindowShuffleCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("WinShuffle")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Shuffle open macOS windows like a deck of cards.")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Grant Access") {
                    coordinator.requestAccessibilityAccess()
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
                    Text("Open a few standard app windows, grant Accessibility access, then refresh.")
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
