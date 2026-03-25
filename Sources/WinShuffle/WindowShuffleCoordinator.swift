import AppKit
import Foundation

@MainActor
final class WindowShuffleCoordinator: ObservableObject {
    @Published private(set) var windows: [AccessibilityWindow] = []
    @Published var status = "Grant Accessibility access to start moving windows."
    @Published var hasAccessibilityAccess = false
    @Published var isAnimating = false
    @Published var lastRefresh = Date.now

    private let animationDuration: Double = 1.35
    private let frameCount = 42
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    func refreshWindows() {
        hasAccessibilityAccess = checkAccessibility(prompt: false)
        guard hasAccessibilityAccess else {
            status = "Accessibility access is required before windows can be shuffled."
            windows = []
            lastRefresh = .now
            return
        }

        windows = AccessibilityWindow.loadMovableWindows(excluding: Bundle.main.bundleIdentifier)
        lastRefresh = .now
        status = windows.isEmpty
            ? "No movable windows found."
            : "Ready to shuffle \(windows.count) window\(windows.count == 1 ? "" : "s")."
    }

    func requestAccessibilityAccess() {
        hasAccessibilityAccess = checkAccessibility(prompt: true)
        status = hasAccessibilityAccess
            ? "Accessibility granted. Refresh to load windows."
            : "Accessibility access was not granted."
        if hasAccessibilityAccess {
            refreshWindows()
        }
    }

    func startMonitoring() {
        stopMonitoring()
        refreshWindows()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isAnimating else {
                    return
                }
                self.refreshWindows()
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]

        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, !self.isAnimating else {
                        return
                    }
                    self.refreshWindows()
                }
            }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    func shuffle() {
        guard !isAnimating else {
            return
        }
        refreshWindows()

        guard hasAccessibilityAccess else {
            return
        }
        guard windows.count > 1 else {
            status = windows.isEmpty ? "No movable windows found." : "At least two windows are needed to shuffle."
            return
        }

        isAnimating = true
        status = "Shuffling \(windows.count) windows."

        let sourceFrames = windows.map(\.frame)
        let targetOrigins = makeShuffledOrigins(for: windows)

        Task {
            defer {
                isAnimating = false
                refreshWindows()
            }

            for frameIndex in 0...frameCount {
                let t = Double(frameIndex) / Double(frameCount)
                let eased = cubicEaseInOut(t)

                for (index, window) in windows.enumerated() {
                    let start = sourceFrames[index].origin
                    let end = targetOrigins[index]
                    let lift = sin(eased * .pi) * (18 + Double(index % 5) * 10)
                    let drift = cos((eased + Double(index) * 0.11) * .pi * 2) * 10

                    let x = start.x + ((end.x - start.x) * eased) + drift
                    let y = start.y + ((end.y - start.y) * eased) + lift
                    AccessibilityWindow.setPosition(CGPoint(x: x, y: y), for: window.element)
                }

                try? await Task.sleep(for: .seconds(animationDuration / Double(frameCount)))
            }

            status = "Shuffle complete."
        }
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func makeShuffledOrigins(for windows: [AccessibilityWindow]) -> [CGPoint] {
        let origins = windows.map(\.frame.origin).shuffled()

        return windows.enumerated().map { index, window in
            let candidate = origins[index]
            let spreadX = CGFloat((index % 4) - 1) * 18
            let spreadY = CGFloat(index % 3) * -16
            return clampedOrigin(
                for: window,
                proposed: CGPoint(x: candidate.x + spreadX, y: candidate.y + spreadY)
            )
        }
    }

    private func clampedOrigin(for window: AccessibilityWindow, proposed: CGPoint) -> CGPoint {
        let minX = window.screenFrame.minX
        let maxX = window.screenFrame.maxX - window.frame.width
        let minY = window.screenFrame.minY
        let maxY = window.screenFrame.maxY - window.frame.height

        return CGPoint(
            x: min(max(proposed.x, minX), maxX),
            y: min(max(proposed.y, minY), maxY)
        )
    }

    private func cubicEaseInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        }

        let shifted = (-2 * t) + 2
        return 1 - pow(shifted, 3) / 2
    }
}
