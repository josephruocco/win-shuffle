import AppKit
import SwiftUI

@MainActor
final class DeckTableController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var status = "No card table on screen."

    private let cardSize = CGSize(width: 152, height: 214)
    private var backdropWindow: DeckBackdropWindow?
    private var controlPanel: DeckControlPanelWindow?
    private var cardWindows: [TerminalCardWindow] = []
    private var selectedCardID: String?

    func createDeck() {
        guard !isPresented else {
            bringToFront()
            return
        }

        guard let visibleFrame = activeVisibleFrame() else {
            status = "No visible screen available for the card table."
            return
        }

        let backdrop = DeckBackdropWindow(frame: visibleFrame)
        backdrop.orderFrontRegardless()
        backdropWindow = backdrop
        showControlPanel(visibleFrame: visibleFrame)

        let startFrame = CGRect(
            x: visibleFrame.midX - (cardSize.width / 2),
            y: visibleFrame.midY - (cardSize.height / 2),
            width: cardSize.width,
            height: cardSize.height
        )

        var windows: [TerminalCardWindow] = []
        for (index, card) in DeckCard.fullDeck.enumerated() {
            let offset = CGFloat(index % 6) * 2
            let frame = startFrame.offsetBy(dx: offset, dy: -offset)
            let state = DeckCardState(card: card, isFaceUp: true)
            let window = TerminalCardWindow(state: state, frame: frame) { [weak self] id in
                Task { @MainActor in
                    self?.selectCard(withID: id)
                }
            }
            window.orderFrontRegardless()
            windows.append(window)
        }

        cardWindows = windows
        isPresented = true
        selectedCardID = windows.first?.cardID
        syncControlPanel()
        status = "52-card deck created. Double-click any card to flip it."
        animate(to: .table, shuffled: false)
    }

    func shuffleDeck() {
        guard isPresented else {
            createDeck()
            return
        }

        animate(to: .scatter, shuffled: true)
    }

    func stackDeck() {
        guard isPresented else {
            createDeck()
            return
        }

        setAllCards(faceUp: false)
        animate(to: .stack, shuffled: false)
        status = "Deck stacked in the top-left corner."
    }

    func flipAllCards() {
        guard isPresented else {
            return
        }

        cardWindows.forEach { $0.flip() }
        status = "All cards flipped."
    }

    func revealAllCards() {
        guard isPresented else {
            return
        }

        setAllCards(faceUp: true)
        status = "All cards turned face up."
    }

    func resetLayout() {
        guard isPresented else {
            return
        }

        setAllCards(faceUp: true)
        animate(to: .table, shuffled: false)
    }

    func flipSelectedCard() {
        guard let window = selectedWindow else {
            status = "Select a card window first."
            syncControlPanel()
            return
        }

        window.flip()
        status = "Flipped \(window.cardLabel)."
        syncControlPanel()
    }

    func closeDeck() {
        cardWindows.forEach { $0.close() }
        cardWindows.removeAll()
        backdropWindow?.close()
        backdropWindow = nil
        controlPanel?.close()
        controlPanel = nil
        isPresented = false
        selectedCardID = nil
        status = "Card table cleared."
    }

    private func animate(to layout: DeckLayout, shuffled: Bool) {
        guard let visibleFrame = activeVisibleFrame(), !cardWindows.isEmpty else {
            return
        }

        var windows = cardWindows
        if shuffled {
            windows.shuffle()
        }

        let frames = targetFrames(for: windows.count, layout: layout, visibleFrame: visibleFrame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration(for: layout)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            for (index, window) in windows.enumerated() {
                guard index < frames.count else { continue }
                window.orderFrontRegardless()
                window.animator().setFrame(frames[index], display: true)
            }
        }

        cardWindows = windows
        if layout == .table {
            status = "Cards dealt across the table."
        } else if layout == .scatter {
            status = "Cards shuffled."
        }
        syncControlPanel()
    }

    private func animationDuration(for layout: DeckLayout) -> TimeInterval {
        switch layout {
        case .table:
            return 0.9
        case .scatter:
            return 0.75
        case .stack:
            return 0.55
        }
    }

    private func targetFrames(for count: Int, layout: DeckLayout, visibleFrame: CGRect) -> [CGRect] {
        switch layout {
        case .table:
            return tableFrames(count: count, visibleFrame: visibleFrame)
        case .scatter:
            return scatterFrames(count: count, visibleFrame: visibleFrame)
        case .stack:
            return stackFrames(count: count, visibleFrame: visibleFrame)
        }
    }

    private func tableFrames(count: Int, visibleFrame: CGRect) -> [CGRect] {
        let columns = 13
        let rows = 4
        let horizontalGap = min(18.0, (visibleFrame.width - (CGFloat(columns) * cardSize.width)) / CGFloat(max(columns - 1, 1)))
        let verticalGap = min(22.0, (visibleFrame.height - (CGFloat(rows) * cardSize.height)) / CGFloat(max(rows - 1, 1)))
        let totalWidth = (CGFloat(columns) * cardSize.width) + (CGFloat(columns - 1) * horizontalGap)
        let totalHeight = (CGFloat(rows) * cardSize.height) + (CGFloat(rows - 1) * verticalGap)
        let startX = visibleFrame.midX - (totalWidth / 2)
        let startY = visibleFrame.midY - (totalHeight / 2)

        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let row = index / columns
            let column = index % columns
            let x = startX + (CGFloat(column) * (cardSize.width + horizontalGap))
            let y = startY + (CGFloat(row) * (cardSize.height + verticalGap))
            frames.append(CGRect(x: x, y: y, width: cardSize.width, height: cardSize.height))
        }

        return frames
    }

    private func scatterFrames(count: Int, visibleFrame: CGRect) -> [CGRect] {
        let centerX = visibleFrame.midX
        let centerY = visibleFrame.midY
        let baseRadius = min(visibleFrame.width, visibleFrame.height) * 0.22
        let safeCount = max(count, 1)

        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let fraction = Double(index) / Double(safeCount)
            let angle = fraction * Double.pi * 2
            let ring = baseRadius + (CGFloat(index % 4) * 24)
            let x = centerX + (CGFloat(cos(angle)) * ring) - (cardSize.width / 2)
            let y = centerY + (CGFloat(sin(angle)) * ring) - (cardSize.height / 2)
            frames.append(CGRect(x: x, y: y, width: cardSize.width, height: cardSize.height))
        }

        return frames
    }

    private func stackFrames(count: Int, visibleFrame: CGRect) -> [CGRect] {
        let startX = visibleFrame.minX + 28
        let startY = visibleFrame.maxY - cardSize.height - 32

        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let offset = CGFloat(index) * 0.55
            frames.append(
                CGRect(
                    x: startX + offset,
                    y: startY - offset,
                    width: cardSize.width,
                    height: cardSize.height
                )
            )
        }

        return frames
    }

    private func setAllCards(faceUp: Bool) {
        cardWindows.forEach { $0.setFaceUp(faceUp) }
        syncControlPanel()
    }

    private func bringToFront() {
        backdropWindow?.orderFrontRegardless()
        controlPanel?.orderFrontRegardless()
        cardWindows.forEach { $0.orderFrontRegardless() }
        status = "Card table already open."
        syncControlPanel()
    }

    private func activeVisibleFrame() -> CGRect? {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
    }

    private var selectedWindow: TerminalCardWindow? {
        cardWindows.first(where: { $0.cardID == selectedCardID })
    }

    private func selectCard(withID id: String) {
        selectedCardID = id
        if let window = selectedWindow {
            status = "Selected \(window.cardLabel)."
        }
        syncControlPanel()
    }

    private func showControlPanel(visibleFrame: CGRect) {
        guard controlPanel == nil else {
            syncControlPanel()
            return
        }

        let panelSize = CGSize(width: 252, height: 188)
        let panelOrigin = CGPoint(
            x: visibleFrame.minX + 24,
            y: visibleFrame.maxY - panelSize.height - 24
        )
        let frame = CGRect(origin: panelOrigin, size: panelSize)
        let panel = DeckControlPanelWindow(frame: frame)
        controlPanel = panel
        syncControlPanel()
        panel.orderFrontRegardless()
    }

    private func syncControlPanel() {
        let selectedLabel = selectedWindow?.cardLabel ?? "None"
        controlPanel?.update(
            selectedLabel: selectedLabel,
            status: status,
            canFlipSelected: selectedWindow != nil,
            onFlipSelected: { [weak self] in
                Task { @MainActor in
                    self?.flipSelectedCard()
                }
            },
            onStackDeck: { [weak self] in
                Task { @MainActor in
                    self?.stackDeck()
                }
            },
            onShuffleDeck: { [weak self] in
                Task { @MainActor in
                    self?.shuffleDeck()
                }
            },
            onDealDeck: { [weak self] in
                Task { @MainActor in
                    self?.resetLayout()
                }
            },
            onRevealDeck: { [weak self] in
                Task { @MainActor in
                    self?.revealAllCards()
                }
            }
        )
    }
}

private enum DeckLayout {
    case table
    case scatter
    case stack
}

private final class DeckCardState: ObservableObject, Identifiable {
    let card: DeckCard
    @Published var isFaceUp: Bool

    init(card: DeckCard, isFaceUp: Bool) {
        self.card = card
        self.isFaceUp = isFaceUp
    }

    var id: String {
        card.id
    }
}

private final class DeckBackdropWindow: NSWindow {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

private final class DeckControlPanelWindow: NSPanel {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        title = "Deck Controls"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
    }

    func update(
        selectedLabel: String,
        status: String,
        canFlipSelected: Bool,
        onFlipSelected: @escaping () -> Void,
        onStackDeck: @escaping () -> Void,
        onShuffleDeck: @escaping () -> Void,
        onDealDeck: @escaping () -> Void,
        onRevealDeck: @escaping () -> Void
    ) {
        hostingView.rootView = AnyView(
            DeckControlPanelView(
                selectedLabel: selectedLabel,
                status: status,
                canFlipSelected: canFlipSelected,
                onFlipSelected: onFlipSelected,
                onStackDeck: onStackDeck,
                onShuffleDeck: onShuffleDeck,
                onDealDeck: onDealDeck,
                onRevealDeck: onRevealDeck
            )
        )
    }
}

private final class TerminalCardWindow: NSWindow {
    private let state: DeckCardState
    private let onSelect: (String) -> Void

    init(state: DeckCardState, frame: CGRect, onSelect: @escaping (String) -> Void) {
        self.state = state
        self.onSelect = onSelect
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: TerminalCardView(state: state))
    }

    var cardID: String {
        state.card.id
    }

    var cardLabel: String {
        state.card.suitLine.capitalized
    }

    func flip() {
        state.isFaceUp.toggle()
    }

    func setFaceUp(_ faceUp: Bool) {
        state.isFaceUp = faceUp
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onSelect(cardID)
        if event.clickCount == 2 {
            flip()
        }
    }
}

private struct DeckControlPanelView: View {
    let selectedLabel: String
    let status: String
    let canFlipSelected: Bool
    let onFlipSelected: () -> Void
    let onStackDeck: () -> Void
    let onShuffleDeck: () -> Void
    let onDealDeck: () -> Void
    let onRevealDeck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Selected Card")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(selectedLabel)
                    .font(.headline.monospaced())
            }

            HStack(spacing: 8) {
                Button("Flip Selected", action: onFlipSelected)
                    .disabled(!canFlipSelected)
                Button("Stack Deck", action: onStackDeck)
            }

            HStack(spacing: 8) {
                Button("Deal", action: onDealDeck)
                Button("Shuffle", action: onShuffleDeck)
                Button("Reveal", action: onRevealDeck)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct TerminalCardView: View {
    @ObservedObject var state: DeckCardState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                trafficLight(Color(red: 1, green: 0.37, blue: 0.33))
                trafficLight(Color(red: 1, green: 0.74, blue: 0.18))
                trafficLight(Color(red: 0.16, green: 0.79, blue: 0.34))
                Spacer()
                Text(headerTitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Color(red: 0.14, green: 0.15, blue: 0.17))

            ZStack {
                if state.isFaceUp {
                    faceUpBody
                } else {
                    faceDownBody
                }
            }
            .padding(8)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.11, blue: 0.1),
                        Color(red: 0.08, green: 0.07, blue: 0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }

    private var headerTitle: String {
        "deck://card"
    }

    private var faceUpBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.94, green: 0.92, blue: 0.84))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(cardInk.opacity(0.24), lineWidth: 1)

            Text(faceUpText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(cardInk)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var faceDownBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.11, green: 0.16, blue: 0.11))

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.42, green: 0.91, blue: 0.46).opacity(0.35), lineWidth: 1)

            Text(faceDownText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(red: 0.42, green: 0.91, blue: 0.46))
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var cardInk: Color {
        switch state.card.suit {
        case .diamonds, .hearts:
            return Color(red: 0.78, green: 0.18, blue: 0.24)
        case .clubs, .spades:
            return Color(red: 0.12, green: 0.14, blue: 0.18)
        }
    }

    private var faceUpText: String {
        let rank = state.card.rank.rawValue
        let pip = state.card.suit.pip
        let suitName = state.card.suit.rawValue
        let top = "\(rank) \(pip)"
        let bottom = "\(pip) \(rank)"
        return """
        +------------------+
        |\(padRight(top, to: 18))|
        |\(padRight(suitName, to: 18))|
        |                  |
        |       \(padCenter(pip, to: 4))       |
        |      \(padCenter(rank, to: 6))      |
        |   DOUBLE-CLICK =   |
        |   FLIP / DRAG OK   |
        |                  |
        |\(padLeft(bottom, to: 18))|
        +------------------+
        """
    }

    private var faceDownText: String {
        """
        +------------------+
        |##################|
        |## WINSHUFFLE ###|
        |##################|
        |## RETRO DECK ###|
        |## FACE   DOWN ##|
        |## SELECT + FLIP#|
        |## STACK READY ##|
        |##################|
        +------------------+
        """
    }

    private func padLeft(_ value: String, to width: Int) -> String {
        String(repeating: " ", count: max(width - value.count, 0)) + value
    }

    private func padRight(_ value: String, to width: Int) -> String {
        value + String(repeating: " ", count: max(width - value.count, 0))
    }

    private func padCenter(_ value: String, to width: Int) -> String {
        let totalPadding = max(width - value.count, 0)
        let leading = totalPadding / 2
        let trailing = totalPadding - leading
        return String(repeating: " ", count: leading) + value + String(repeating: " ", count: trailing)
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
    }
}
