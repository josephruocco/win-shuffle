import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class WindowPreviewOverlayAnimator {
    func preview(
        windows: [AccessibilityWindow],
        sourceFrames: [CGRect],
        deckAnchors: [CGPoint],
        intensity: Double,
        duration: Double
    ) async {
        let overlays = windows.enumerated().compactMap { index, window -> CardOverlayWindow? in
            guard let image = snapshot(for: window) ?? placeholderImage(for: window, size: sourceFrames[index].size) else {
                return nil
            }

            let overlay = CardOverlayWindow(frame: sourceFrames[index], image: image, title: window.title)
            overlay.orderFrontRegardless()
            return overlay
        }

        guard !overlays.isEmpty else {
            return
        }

        let previewFrames = 26
        let previewDuration = min(0.95, duration * 0.42)

        for frameIndex in 0...previewFrames {
            let progress = Double(frameIndex) / Double(previewFrames)
            let phase = previewPhase(for: progress)

            for (index, overlay) in overlays.enumerated() {
                let targetOrigin = previewOrigin(
                    at: phase,
                    index: index,
                    start: sourceFrames[index].origin,
                    deckAnchor: deckAnchors[index],
                    intensity: intensity
                )
                overlay.setFrameOrigin(targetOrigin)
                overlay.alphaValue = alpha(for: phase)
            }

            try? await Task.sleep(for: .seconds(previewDuration / Double(previewFrames)))
        }

        overlays.forEach { $0.close() }
    }

    private func previewOrigin(
        at phase: PreviewPhase,
        index: Int,
        start: CGPoint,
        deckAnchor: CGPoint,
        intensity: Double
    ) -> CGPoint {
        switch phase {
        case .gather(let amount):
            let stackOffset = CGPoint(
                x: CGFloat(index) * (7 * intensity),
                y: CGFloat(index % 3) * (-5 * intensity)
            )
            return interpolate(
                from: start,
                to: CGPoint(x: deckAnchor.x + stackOffset.x, y: deckAnchor.y + stackOffset.y),
                amount: amount
            )

        case .fan(let amount):
            let fanOffset = CGPoint(
                x: CGFloat(index) * (34 * intensity),
                y: CGFloat(index % 2 == 0 ? -index : index) * (10 * intensity)
            )
            let base = CGPoint(x: deckAnchor.x + fanOffset.x, y: deckAnchor.y + fanOffset.y)
            let sweep = CGPoint(
                x: cos((Double(index) * 0.38) + (amount * .pi)) * (24 * intensity),
                y: sin((Double(index) * 0.33) + (amount * .pi)) * (16 * intensity)
            )
            return CGPoint(x: base.x + sweep.x, y: base.y + sweep.y)
        }
    }

    private func alpha(for phase: PreviewPhase) -> CGFloat {
        switch phase {
        case .gather(let amount):
            return 0.58 + (amount * 0.22)
        case .fan(let amount):
            return 0.8 - (amount * 0.12)
        }
    }

    private func previewPhase(for progress: Double) -> PreviewPhase {
        if progress < 0.58 {
            return .gather(cubicEaseInOut(progress / 0.58))
        }

        return .fan(cubicEaseInOut((progress - 0.58) / 0.42))
    }

    private func snapshot(for window: AccessibilityWindow) -> NSImage? {
        if let windowID = window.windowID,
           let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
           ) {
            return NSImage(cgImage: cgImage, size: .zero)
        }

        return nil
    }

    private func placeholderImage(for window: AccessibilityWindow, size: CGSize) -> NSImage? {
        let width = max(size.width, 220)
        let height = max(size.height, 140)
        let image = NSImage(size: CGSize(width: width, height: height))
        image.lockFocus()

        let background = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.2, alpha: 0.92).setFill()
        background.fill()

        let accent = NSBezierPath(roundedRect: NSRect(x: 18, y: height - 34, width: width - 36, height: 6), xRadius: 3, yRadius: 3)
        NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.27, alpha: 0.95).setFill()
        accent.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)
        ]

        NSString(string: window.title).draw(in: NSRect(x: 18, y: height - 78, width: width - 36, height: 28), withAttributes: titleAttributes)
        NSString(string: window.appName).draw(in: NSRect(x: 18, y: height - 108, width: width - 36, height: 22), withAttributes: subtitleAttributes)

        image.unlockFocus()
        return image
    }

    private func interpolate(from: CGPoint, to: CGPoint, amount: Double) -> CGPoint {
        CGPoint(
            x: from.x + ((to.x - from.x) * amount),
            y: from.y + ((to.y - from.y) * amount)
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

private enum PreviewPhase {
    case gather(Double)
    case fan(Double)
}

private final class CardOverlayWindow: NSWindow {
    init(frame: CGRect, image: NSImage, title: String) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        contentView = NSHostingView(rootView: OverlayCardView(image: image, title: title))
    }
}

private struct OverlayCardView: View {
    let image: NSImage
    let title: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.68)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(16)
        }
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 18)
    }
}
