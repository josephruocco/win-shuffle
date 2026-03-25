import AppKit
import Foundation

@MainActor
final class WindowShuffleCoordinator: ObservableObject {
    @Published private(set) var windows: [AccessibilityWindow] = []
    @Published var status = "Grant Accessibility access to start moving windows."
    @Published var hasAccessibilityAccess = false
    @Published var isAnimating = false
    @Published var lastRefresh = Date.now
    @Published private(set) var canRestore = false

    private let animationDuration: Double = 1.8
    private let frameCount = 90
    private let resizeFrameCount = 30
    private let settings: ShuffleSettings
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastArrangement: [StoredWindowArrangement] = []

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
        lastArrangement = windows.map { StoredWindowArrangement(element: $0.element, frame: $0.frame) }
        canRestore = !lastArrangement.isEmpty
        let motion = settings.selectedPreset.motion
        let normalizedFrames = makeNormalizedFrames(for: windows)
        let targetOrigins = makeShuffledOrigins(
            for: normalizedFrames,
            shape: settings.selectedShape,
            radiusScale: settings.clusterRadius,
            intensity: settings.intensityScale,
            motion: motion
        )
        let deckAnchors = makeDeckAnchors(
            for: normalizedFrames,
            radiusScale: settings.clusterRadius,
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
                        count: windows.count,
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

    func restore() {
        guard !isAnimating, !lastArrangement.isEmpty else {
            return
        }

        isAnimating = true
        status = "Restoring windows."

        let arrangements = lastArrangement
        Task {
            defer {
                isAnimating = false
                status = "Windows restored."
                refreshWindows()
            }

            let restoreFrames = 40
            let currentFrames = arrangements.map { arrangement in
                currentFrame(for: arrangement.element) ?? arrangement.frame
            }

            for frameIndex in 0...restoreFrames {
                let t = Double(frameIndex) / Double(restoreFrames)
                let eased = smootherStep(t)

                for (index, arrangement) in arrangements.enumerated() {
                    let start = currentFrames[index]
                    let end = arrangement.frame
                    let size = CGSize(
                        width: start.width + ((end.width - start.width) * eased),
                        height: start.height + ((end.height - start.height) * eased)
                    )
                    let origin = CGPoint(
                        x: start.origin.x + ((end.origin.x - start.origin.x) * eased),
                        y: start.origin.y + ((end.origin.y - start.origin.y) * eased)
                    )

                    AccessibilityWindow.setSize(size, for: arrangement.element)
                    AccessibilityWindow.setPosition(origin, for: arrangement.element)
                }

                try? await Task.sleep(for: .seconds(0.75 / Double(restoreFrames)))
            }
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
        shape: ShuffleShape,
        radiusScale: Double,
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> [CGPoint] {
        let visible = clusterVisibleFrame(for: frames) ?? NSScreen.main?.visibleFrame ?? .zero
        let center = CGPoint(x: visible.midX, y: visible.midY)

        return frames.enumerated().map { index, frame in
            let candidate = targetOrigin(
                shape: shape,
                index: index,
                count: frames.count,
                centeredIndex: centeredOffset(for: index, count: frames.count),
                center: center,
                visible: visible,
                radiusScale: radiusScale,
                intensity: intensity,
                motion: motion
            )
            return clampedOrigin(
                frame: frame,
                screenFrame: visible,
                proposed: candidate
            )
        }
    }

    private func makeDeckAnchors(
        for frames: [CGRect],
        radiusScale: Double,
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> [CGPoint] {
        let visible = clusterVisibleFrame(for: frames) ?? NSScreen.main?.visibleFrame ?? .zero
        let deckCenter = CGPoint(
            x: visible.midX + (motion.deckOffset.x * intensity * 0.28 * radiusScale),
            y: visible.midY + (motion.deckOffset.y * intensity * 0.22 * radiusScale)
        )

        return frames.enumerated().map { index, frame in
            let centeredIndex = centeredOffset(for: index, count: frames.count)
            let fanX = centeredIndex * (motion.fanStep.width * intensity * 0.62)
            let fanY = sin(Double(centeredIndex) * 0.65) * (motion.fanStep.height * intensity * 0.75)
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

    private func smootherStep(_ t: Double) -> Double {
        t * t * t * (t * ((t * 6) - 15) + 10)
    }

    private func shufflePhase(for progress: Double) -> ShufflePhase {
        if progress < 0.28 {
            return .gather(smootherStep(progress / 0.28))
        }

        if progress < 0.54 {
            return .fan(smootherStep((progress - 0.28) / 0.26))
        }

        return .deal(smootherStep((progress - 0.54) / 0.46))
    }

    private func animatedOrigin(
        at phase: ShufflePhase,
        index: Int,
        count: Int,
        start: CGPoint,
        deckAnchor: CGPoint,
        target: CGPoint,
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> CGPoint {
        let centeredIndex = centeredOffset(for: index, count: count)

        switch phase {
        case .gather(let amount):
            let stackOffset = CGPoint(
                x: centeredIndex * (motion.gatherStackStep.width * intensity),
                y: CGFloat(index % 3) * (motion.gatherStackStep.height * intensity)
            )
            return interpolate(
                from: start,
                to: CGPoint(x: deckAnchor.x + stackOffset.x, y: deckAnchor.y + stackOffset.y),
                amount: amount
            )

        case .fan(let amount):
            let fanOffset = CGPoint(
                x: centeredIndex * (motion.fanStep.width * intensity * 0.68),
                y: sin(Double(centeredIndex) * 0.7) * (motion.fanStep.height * intensity * 0.82)
            )
            let base = CGPoint(x: deckAnchor.x + fanOffset.x, y: deckAnchor.y + fanOffset.y)
            let sweep = CGPoint(
                x: cos((Double(centeredIndex) * 0.38) + (amount * .pi)) * (motion.fanSweep.width * intensity * 0.72),
                y: sin((Double(centeredIndex) * 0.32) + (amount * .pi * 1.08)) * (motion.fanSweep.height * intensity * 0.68)
            )
            return CGPoint(x: base.x + sweep.x, y: base.y + sweep.y)

        case .deal(let amount):
            let stagger = min(max(amount - (Double(index) * motion.dealStaggerStep), 0), 1)
            let eased = smootherStep(stagger)
            let arcHeight = sin(eased * .pi) * ((motion.dealArcBase + Double(index % 4) * motion.dealArcBonus) * intensity * 0.82)
            let drift = cos((eased * .pi * 2) + Double(centeredIndex) * 0.35) * (motion.dealDrift * intensity * 0.5)
            let dealt = interpolate(from: deckAnchor, to: target, amount: eased)
            return CGPoint(x: dealt.x + drift, y: dealt.y + arcHeight)
        }
    }

    private func targetOrigin(
        shape: ShuffleShape,
        index: Int,
        count: Int,
        centeredIndex: CGFloat,
        center: CGPoint,
        visible: CGRect,
        radiusScale: Double,
        intensity: Double,
        motion: ShuffleMotionProfile
    ) -> CGPoint {
        switch shape.id {
        case ShuffleShape.fan.id:
            let widthStep = motion.targetScatter.width * intensity * 0.88 * radiusScale
            let curveHeight = min(visible.height * 0.12, 42 * intensity * radiusScale)
            return CGPoint(
                x: center.x + (centeredIndex * widthStep),
                y: center.y - (pow(Double(centeredIndex), 2) * 0.9) + curveHeight
            )

        case ShuffleShape.stack.id:
            return CGPoint(
                x: center.x + (centeredIndex * motion.gatherStackStep.width * intensity * 0.7),
                y: center.y + (CGFloat(index % 4) * motion.gatherStackStep.height * intensity * 0.6)
            )

        case ShuffleShape.scatter.id:
            let columns = max(2, Int(ceil(sqrt(Double(count)))))
            let rows = max(1, Int(ceil(Double(count) / Double(columns))))
            let column = index % columns
            let row = index / columns
            let columnOffset = CGFloat(column) - (CGFloat(columns - 1) / 2)
            let rowOffset = CGFloat(row) - (CGFloat(rows - 1) / 2)
            return CGPoint(
                x: center.x + (columnOffset * motion.targetScatter.width * intensity * 0.95 * radiusScale),
                y: center.y + (rowOffset * abs(motion.targetScatter.height) * intensity * 0.85 * radiusScale)
            )

        default:
            let radius = min(visible.width, visible.height) * (0.09 + (0.045 * intensity * radiusScale))
            let angle = ((Double(index) / Double(max(count, 1))) * .pi * 2) - (.pi / 2)
            let ring = radius + CGFloat(index % 2) * (14 * intensity * radiusScale)
            return CGPoint(
                x: center.x + (cos(angle) * ring),
                y: center.y + (sin(angle) * ring)
            )
        }
    }

    private func centeredOffset(for index: Int, count: Int) -> CGFloat {
        CGFloat(index) - (CGFloat(count - 1) / 2)
    }

    private func currentFrame(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue
        else {
            return nil
        }

        let pointValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pointValue, .cgPoint, &origin)
        AXValueGetValue(sizeAXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
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

private struct StoredWindowArrangement {
    let element: AXUIElement
    let frame: CGRect
}
