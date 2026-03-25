import AppKit
import Foundation

@MainActor
final class WindowShuffleCoordinator: ObservableObject {
    @Published private(set) var windows: [AccessibilityWindow] = []
    @Published var status = "Grant Accessibility access to start moving windows."
    @Published var hasAccessibilityAccess = false
    @Published var isAnimating = false
    @Published var lastRefresh = Date.now

    private let animationDuration: Double = 1.8
    private let frameCount = 60
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

        let windows = windows
        let sourceFrames = windows.map(\.frame)
        let targetOrigins = makeShuffledOrigins(for: windows)
        let deckAnchors = makeDeckAnchors(for: windows)

        Task {
            defer {
                isAnimating = false
                refreshWindows()
            }

            windows.enumerated().forEach { index, window in
                AccessibilityWindow.raise(window.element)
                if index < windows.count - 1 {
                    _ = AXUIElementSetMessagingTimeout(window.element, 0.05)
                }
            }

            for frameIndex in 0...frameCount {
                let t = Double(frameIndex) / Double(frameCount)
                let phase = shufflePhase(for: t)

                for (index, window) in windows.enumerated() {
                    let origin = animatedOrigin(
                        at: phase,
                        index: index,
                        start: sourceFrames[index].origin,
                        deckAnchor: deckAnchors[index],
                        target: targetOrigins[index]
                    )
                    AccessibilityWindow.setPosition(origin, for: window.element)
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
            let spreadX = CGFloat((index % 5) - 2) * 26
            let spreadY = CGFloat(index % 4) * -18
            return clampedOrigin(
                for: window,
                proposed: CGPoint(x: candidate.x + spreadX, y: candidate.y + spreadY)
            )
        }
    }

    private func makeDeckAnchors(for windows: [AccessibilityWindow]) -> [CGPoint] {
        let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let deckCenter = CGPoint(
            x: visible.midX - 180,
            y: visible.midY - 110
        )

        return windows.enumerated().map { index, window in
            let fanX = CGFloat(index) * 18
            let fanY = CGFloat(index % 2 == 0 ? -index : index) * 5
            return clampedOrigin(
                for: window,
                proposed: CGPoint(
                    x: deckCenter.x + fanX,
                    y: deckCenter.y + fanY
                )
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

    private func shufflePhase(for progress: Double) -> ShufflePhase {
        if progress < 0.33 {
            return .gather(cubicEaseInOut(progress / 0.33))
        }

        if progress < 0.56 {
            return .fan(cubicEaseInOut((progress - 0.33) / 0.23))
        }

        return .deal(cubicEaseInOut((progress - 0.56) / 0.44))
    }

    private func animatedOrigin(
        at phase: ShufflePhase,
        index: Int,
        start: CGPoint,
        deckAnchor: CGPoint,
        target: CGPoint
    ) -> CGPoint {
        switch phase {
        case .gather(let amount):
            let stackOffset = CGPoint(x: CGFloat(index) * 8, y: CGFloat(index % 3) * -6)
            return interpolate(
                from: start,
                to: CGPoint(x: deckAnchor.x + stackOffset.x, y: deckAnchor.y + stackOffset.y),
                amount: amount
            )

        case .fan(let amount):
            let fanOffset = CGPoint(
                x: CGFloat(index) * 28,
                y: CGFloat(index % 2 == 0 ? -index : index) * 9
            )
            let base = CGPoint(x: deckAnchor.x + fanOffset.x, y: deckAnchor.y + fanOffset.y)
            let sweep = CGPoint(
                x: cos((Double(index) * 0.45) + (amount * .pi)) * 18,
                y: sin((Double(index) * 0.35) + (amount * .pi * 1.1)) * 12
            )
            return CGPoint(x: base.x + sweep.x, y: base.y + sweep.y)

        case .deal(let amount):
            let stagger = min(max(amount - (Double(index) * 0.045), 0), 1)
            let eased = cubicEaseInOut(stagger)
            let arcHeight = sin(eased * .pi) * (42 + Double(index % 4) * 10)
            let drift = cos((eased * .pi * 2) + Double(index) * 0.5) * 12
            let dealt = interpolate(from: deckAnchor, to: target, amount: eased)
            return CGPoint(x: dealt.x + drift, y: dealt.y + arcHeight)
        }
    }

    private func interpolate(from: CGPoint, to: CGPoint, amount: Double) -> CGPoint {
        CGPoint(
            x: from.x + ((to.x - from.x) * amount),
            y: from.y + ((to.y - from.y) * amount)
        )
    }
}

private enum ShufflePhase {
    case gather(Double)
    case fan(Double)
    case deal(Double)
}
