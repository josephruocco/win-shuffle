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
    private let resizeFrameCount = 22
    private let settings: ShuffleSettings
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(settings: ShuffleSettings) {
        self.settings = settings
    }

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
        let motion = settings.selectedPreset.motion
        let normalizedFrames = makeNormalizedFrames(for: windows)
        let targetOrigins = makeShuffledOrigins(
            for: normalizedFrames,
            intensity: settings.intensityScale,
            motion: motion
        )
        let deckAnchors = makeDeckAnchors(
            for: normalizedFrames,
            intensity: settings.intensityScale,
            motion: motion
        )
        let duration = settings.animationDuration

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

            status = "Normalizing window sizes."
            for frameIndex in 0...resizeFrameCount {
                let t = Double(frameIndex) / Double(resizeFrameCount)
                let eased = cubicEaseInOut(t)

                for (index, window) in windows.enumerated() {
                    let normalized = normalizedFrames[index]
                    let size = CGSize(
                        width: sourceFrames[index].width + ((normalized.width - sourceFrames[index].width) * eased),
                        height: sourceFrames[index].height + ((normalized.height - sourceFrames[index].height) * eased)
                    )
                    let origin = CGPoint(
                        x: sourceFrames[index].origin.x + ((normalized.origin.x - sourceFrames[index].origin.x) * eased),
                        y: sourceFrames[index].origin.y + ((normalized.origin.y - sourceFrames[index].origin.y) * eased)
                    )

                    AccessibilityWindow.setSize(size, for: window.element)
                    AccessibilityWindow.setPosition(origin, for: window.element)
                }

                try? await Task.sleep(for: .seconds((duration * 0.28) / Double(resizeFrameCount)))
            }

            status = "Shuffling \(windows.count) windows."

            for frameIndex in 0...frameCount {
                let t = Double(frameIndex) / Double(frameCount)
                let phase = shufflePhase(for: t)

                for (index, window) in windows.enumerated() {
                    let origin = animatedOrigin(
                        at: phase,
                        index: index,
                        start: normalizedFrames[index].origin,
                        deckAnchor: deckAnchors[index],
                        target: targetOrigins[index],
                        intensity: settings.intensityScale,
                        motion: motion
                    )
                    AccessibilityWindow.setSize(normalizedFrames[index].size, for: window.element)
                    AccessibilityWindow.setPosition(origin, for: window.element)
                }

                try? await Task.sleep(for: .seconds((duration * 0.72) / Double(frameCount)))
            }

            status = "Shuffle complete."
        }
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func makeNormalizedFrames(for windows: [AccessibilityWindow]) -> [CGRect] {
        windows.map { window in
            let targetSize = preferredShuffleSize(for: window.screenFrame)
            let origin = CGPoint(
                x: min(max(window.frame.minX, window.screenFrame.minX), window.screenFrame.maxX - targetSize.width),
                y: min(max(window.frame.minY, window.screenFrame.minY), window.screenFrame.maxY - targetSize.height)
            )
            return CGRect(origin: origin, size: targetSize)
        }
    }

    private func makeShuffledOrigins(
        for frames: [CGRect],
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> [CGPoint] {
        let visible = clusterVisibleFrame(for: frames) ?? NSScreen.main?.visibleFrame ?? .zero
        let center = CGPoint(x: visible.midX, y: visible.midY)
        let baseRadius = min(visible.width, visible.height) * (0.12 + (0.06 * intensity))
        let shuffledAngles = Array(0..<frames.count).shuffled().map { index in
            let ratio = Double(index) / Double(max(frames.count, 1))
            return (ratio * .pi * 2) - (.pi / 2)
        }

        return frames.enumerated().map { index, frame in
            let angle = shuffledAngles[index]
            let ring = baseRadius + CGFloat(index % 3) * (18 * intensity)
            let candidate = CGPoint(
                x: center.x + (cos(angle) * ring),
                y: center.y + (sin(angle) * ring)
            )
            let spreadX = CGFloat((index % 5) - 2) * (motion.targetScatter.width * intensity * 0.45)
            let spreadY = CGFloat((index % 4) - 1) * (motion.targetScatter.height * intensity * 0.35)
            return clampedOrigin(
                frame: frame,
                screenFrame: visible,
                proposed: CGPoint(x: candidate.x + spreadX, y: candidate.y + spreadY)
            )
        }
    }

    private func makeDeckAnchors(
        for frames: [CGRect],
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> [CGPoint] {
        let visible = clusterVisibleFrame(for: frames) ?? NSScreen.main?.visibleFrame ?? .zero
        let deckCenter = CGPoint(
            x: visible.midX + (motion.deckOffset.x * intensity * 0.55),
            y: visible.midY + (motion.deckOffset.y * intensity * 0.55)
        )

        return frames.enumerated().map { index, frame in
            let fanX = CGFloat(index) * (motion.fanStep.width * intensity)
            let fanY = CGFloat(index % 2 == 0 ? -index : index) * (motion.fanStep.height * intensity)
            return clampedOrigin(
                frame: frame,
                screenFrame: visible,
                proposed: CGPoint(
                    x: deckCenter.x + fanX,
                    y: deckCenter.y + fanY
                )
            )
        }
    }

    private func clampedOrigin(frame: CGRect, screenFrame: CGRect, proposed: CGPoint) -> CGPoint {
        let minX = screenFrame.minX
        let maxX = screenFrame.maxX - frame.width
        let minY = screenFrame.minY
        let maxY = screenFrame.maxY - frame.height

        return CGPoint(
            x: min(max(proposed.x, minX), maxX),
            y: min(max(proposed.y, minY), maxY)
        )
    }

    private func preferredShuffleSize(for visibleFrame: CGRect) -> CGSize {
        CGSize(
            width: min(300, visibleFrame.width * 0.52),
            height: min(285, visibleFrame.height * 0.56)
        )
    }

    private func visibleScreenFrame(for frame: CGRect) -> CGRect? {
        NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) })?.visibleFrame
    }

    private func clusterVisibleFrame(for frames: [CGRect]) -> CGRect? {
        let matchedFrames = frames.compactMap { visibleScreenFrame(for: $0) }
        guard !matchedFrames.isEmpty else {
            return nil
        }

        var bestFrame = matchedFrames[0]
        var bestCount = 0

        for candidate in matchedFrames {
            let count = matchedFrames.reduce(into: 0) { partialResult, frame in
                if frame.equalTo(candidate) {
                    partialResult += 1
                }
            }

            if count > bestCount {
                bestCount = count
                bestFrame = candidate
            }
        }

        return bestFrame
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
        target: CGPoint,
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> CGPoint {
        switch phase {
        case .gather(let amount):
            let stackOffset = CGPoint(
                x: CGFloat(index) * (motion.gatherStackStep.width * intensity),
                y: CGFloat(index % 3) * (motion.gatherStackStep.height * intensity)
            )
            return interpolate(
                from: start,
                to: CGPoint(x: deckAnchor.x + stackOffset.x, y: deckAnchor.y + stackOffset.y),
                amount: amount
            )

        case .fan(let amount):
            let fanOffset = CGPoint(
                x: CGFloat(index) * (motion.fanStep.width * intensity),
                y: CGFloat(index % 2 == 0 ? -index : index) * (motion.fanStep.height * intensity)
            )
            let base = CGPoint(x: deckAnchor.x + fanOffset.x, y: deckAnchor.y + fanOffset.y)
            let sweep = CGPoint(
                x: cos((Double(index) * 0.45) + (amount * .pi)) * (motion.fanSweep.width * intensity),
                y: sin((Double(index) * 0.35) + (amount * .pi * 1.1)) * (motion.fanSweep.height * intensity)
            )
            return CGPoint(x: base.x + sweep.x, y: base.y + sweep.y)

        case .deal(let amount):
            let stagger = min(max(amount - (Double(index) * motion.dealStaggerStep), 0), 1)
            let eased = cubicEaseInOut(stagger)
            let arcHeight = sin(eased * .pi) * ((motion.dealArcBase + Double(index % 4) * motion.dealArcBonus) * intensity)
            let drift = cos((eased * .pi * 2) + Double(index) * 0.5) * (motion.dealDrift * intensity)
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
