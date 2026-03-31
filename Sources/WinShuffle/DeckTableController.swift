import AppKit
import SwiftUI

@MainActor
final class DeckTableController: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var status = "No card table on screen."

    private let cardSize = CGSize(width: 152, height: 214)
    private let tableauVerticalStep: CGFloat = 34

    private var backdropWindow: DeckBackdropWindow?
    private var controlPanel: DeckControlPanelWindow?
    private var cardWindows: [String: TerminalCardWindow] = [:]
    private var selectedCardID: String?
    private var stockIDs: [String] = []
    private var wasteIDs: [String] = []
    private var foundationIDs: [DeckCard.Suit: [String]] = Dictionary(
        uniqueKeysWithValues: DeckCard.Suit.allCases.map { ($0, []) }
    )
    private var tableauIDs: [[String]] = Array(repeating: [], count: 7)
    private var dealingOrder: [String] = []

    func createDeck() {
        guard !isPresented else {
            bringToFront()
            return
        }

        guard let visibleFrame = activeVisibleFrame() else {
            status = "No visible screen available for solitaire."
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

        for card in DeckCard.fullDeck {
            let state = DeckCardState(card: card, isFaceUp: false)
            let window = TerminalCardWindow(state: state, frame: startFrame) { [weak self] id in
                Task { @MainActor in
                    self?.selectCard(withID: id)
                }
            }
            window.orderFrontRegardless()
            cardWindows[card.id] = window
        }

        isPresented = true
        startSolitaire()
    }

    func startSolitaire() {
        guard isPresented else {
            createDeck()
            return
        }

        selectedCardID = nil
        stockIDs.removeAll()
        wasteIDs.removeAll()
        foundationIDs = Dictionary(uniqueKeysWithValues: DeckCard.Suit.allCases.map { ($0, []) })
        tableauIDs = Array(repeating: [], count: 7)
        dealingOrder.removeAll()

        let deck = DeckCard.fullDeck.shuffled()
        var cursor = 0
        for column in 0..<7 {
            for row in 0...column {
                let card = deck[cursor]
                cursor += 1
                tableauIDs[column].append(card.id)
                let state = state(for: card.id)
                state.isFaceUp = row == column
                dealingOrder.append(card.id)
            }
        }

        for index in cursor..<deck.count {
            let card = deck[index]
            stockIDs.append(card.id)
            state(for: card.id).isFaceUp = false
            dealingOrder.append(card.id)
        }

        status = "Klondike dealt. Draw from stock, then move cards legally."
        layoutSolitaire(animated: true)
        syncControlPanel()
    }

    func shuffleDeck() {
        startSolitaire()
    }

    func stackDeck() {
        guard isPresented, let visibleFrame = activeVisibleFrame() else {
            return
        }

        for id in allCardIDs {
            state(for: id).isFaceUp = false
        }

        let startX = visibleFrame.minX + 28
        let startY = visibleFrame.maxY - cardSize.height - 32
        let ids = allCardIDs

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.55
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (index, id) in ids.enumerated() {
                guard let window = cardWindows[id] else { continue }
                let offset = CGFloat(index) * 0.55
                let frame = CGRect(
                    x: startX + offset,
                    y: startY - offset,
                    width: cardSize.width,
                    height: cardSize.height
                )
                window.orderFrontRegardless()
                window.animator().setFrame(frame, display: true)
            }
        }

        status = "Deck stacked in the top-left corner."
        selectedCardID = nil
        syncControlPanel()
    }

    func drawFromStock() {
        guard isPresented else { return }

        if let next = stockIDs.popLast() {
            state(for: next).isFaceUp = true
            wasteIDs.append(next)
            selectedCardID = next
            status = "Drew \(state(for: next).card.shortLabel)."
        } else if !wasteIDs.isEmpty {
            stockIDs = wasteIDs.reversed()
            wasteIDs.removeAll()
            for id in stockIDs {
                state(for: id).isFaceUp = false
            }
            selectedCardID = nil
            status = "Waste recycled back into stock."
        } else {
            status = "Stock is empty."
        }

        layoutSolitaire(animated: true)
        syncControlPanel()
    }

    func moveSelectedToFoundation() {
        guard let selected = selectedPlayableSelection else {
            status = "Select a movable face-up card first."
            syncControlPanel()
            return
        }

        guard selected.run.count == 1 else {
            status = "Only one card at a time can move to foundation."
            syncControlPanel()
            return
        }

        let id = selected.run[0]
        let card = state(for: id).card
        let foundation = foundationIDs[card.suit, default: []]
        let expectedValue = foundation.count + 1
        guard card.rank.value == expectedValue else {
            status = "Foundation needs \(expectedValue == 1 ? "an Ace" : "the next rank") of \(card.suit.rawValue.capitalized)."
            syncControlPanel()
            return
        }

        remove(run: selected.run, from: selected.origin)
        foundationIDs[card.suit, default: []].append(id)
        selectedCardID = id
        revealTableauTopIfNeeded(afterMovingFrom: selected.origin)
        layoutSolitaire(animated: true)
        status = "Moved \(card.shortLabel) to foundation."
        syncControlPanel()
        checkForWin()
    }

    func moveSelectedToTableau(_ columnIndex: Int) {
        guard let selected = selectedPlayableSelection else {
            status = "Select a movable face-up card first."
            syncControlPanel()
            return
        }

        guard (0..<7).contains(columnIndex) else { return }
        let destination = tableauIDs[columnIndex]
        let movingCard = state(for: selected.run[0]).card

        if let topID = destination.last {
            let topCard = state(for: topID).card
            let descending = movingCard.rank.value == topCard.rank.value - 1
            let alternating = movingCard.suit.isRed != topCard.suit.isRed
            guard descending && alternating else {
                status = "Illegal tableau move."
                syncControlPanel()
                return
            }
        } else {
            guard movingCard.rank == .king else {
                status = "Only Kings can move to an empty tableau column."
                syncControlPanel()
                return
            }
        }

        remove(run: selected.run, from: selected.origin)
        tableauIDs[columnIndex].append(contentsOf: selected.run)
        selectedCardID = selected.run[0]
        revealTableauTopIfNeeded(afterMovingFrom: selected.origin)
        layoutSolitaire(animated: true)
        status = "Moved \(movingCard.shortLabel) to tableau \(columnIndex + 1)."
        syncControlPanel()
    }

    func flipSelectedCard() {
        guard let window = selectedWindow else {
            status = "Select a card window first."
            syncControlPanel()
            return
        }

        let id = window.cardID
        guard let location = cardLocation(for: id) else {
            return
        }

        if case let .tableau(index) = location, tableauIDs[index].last == id, !window.isFaceUp {
            window.setFaceUp(true)
            status = "Flipped \(window.cardLabel)."
        } else {
            status = "Only the top hidden tableau card can be flipped."
        }
        syncControlPanel()
    }

    func revealAllCards() {
        guard isPresented else { return }
        for id in allCardIDs {
            state(for: id).isFaceUp = true
        }
        layoutSolitaire(animated: true)
        status = "All cards revealed."
        syncControlPanel()
    }

    func resetLayout() {
        layoutSolitaire(animated: true)
    }

    func closeDeck() {
        cardWindows.values.forEach { $0.close() }
        cardWindows.removeAll()
        backdropWindow?.close()
        backdropWindow = nil
        controlPanel?.close()
        controlPanel = nil
        isPresented = false
        selectedCardID = nil
        stockIDs.removeAll()
        wasteIDs.removeAll()
        foundationIDs.removeAll()
        tableauIDs.removeAll()
        status = "Card table cleared."
    }

    private func layoutSolitaire(animated: Bool) {
        guard let visibleFrame = activeVisibleFrame() else { return }

        let layouts = currentSolitaireFrames(visibleFrame: visibleFrame)
        let apply = {
            for item in layouts {
                guard let window = self.cardWindows[item.id] else { continue }
                window.orderFrontRegardless()
                if item.isSelected {
                    window.orderFrontRegardless()
                }
                window.setFrame(item.frame, display: true)
            }
        }

        let animate = {
            for item in layouts {
                guard let window = self.cardWindows[item.id] else { continue }
                window.orderFrontRegardless()
                window.animator().setFrame(item.frame, display: true)
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animate()
            }
        } else {
            apply()
        }

        for item in layouts.sorted(by: { $0.order < $1.order }) {
            cardWindows[item.id]?.orderFrontRegardless()
        }
    }

    private func currentSolitaireFrames(visibleFrame: CGRect) -> [LayoutItem] {
        let left = visibleFrame.minX + 26
        let top = visibleFrame.maxY - cardSize.height - 42
        let columnGap: CGFloat = 18
        let rowGap: CGFloat = 26
        let columnWidth = cardSize.width + columnGap
        var items: [LayoutItem] = []

        for (index, id) in stockIDs.enumerated() {
            let offset = min(CGFloat(index), 4) * 0.7
            items.append(LayoutItem(
                id: id,
                frame: CGRect(x: left + offset, y: top - offset, width: cardSize.width, height: cardSize.height),
                order: index,
                isSelected: id == selectedCardID
            ))
        }

        for (index, id) in wasteIDs.enumerated() {
            let offset = min(CGFloat(index), 3) * 16
            items.append(LayoutItem(
                id: id,
                frame: CGRect(x: left + columnWidth + offset, y: top, width: cardSize.width, height: cardSize.height),
                order: 100 + index,
                isSelected: id == selectedCardID
            ))
        }

        let foundationStartX = left + (columnWidth * 3.4)
        for (foundationIndex, suit) in DeckCard.Suit.allCases.enumerated() {
            let pile = foundationIDs[suit, default: []]
            for (index, id) in pile.enumerated() {
                items.append(LayoutItem(
                    id: id,
                    frame: CGRect(
                        x: foundationStartX + CGFloat(foundationIndex) * columnWidth,
                        y: top,
                        width: cardSize.width,
                        height: cardSize.height
                    ),
                    order: 200 + index + (foundationIndex * 20),
                    isSelected: id == selectedCardID
                ))
            }
        }

        let tableauY = top - cardSize.height - rowGap
        for column in 0..<7 {
            let pile = tableauIDs[column]
            for (depth, id) in pile.enumerated() {
                let state = state(for: id)
                let y = tableauY - (CGFloat(depth) * (state.isFaceUp ? tableauVerticalStep : 18))
                let selectedLift: CGFloat = id == selectedCardID ? 16 : 0
                items.append(LayoutItem(
                    id: id,
                    frame: CGRect(
                        x: left + CGFloat(column) * columnWidth,
                        y: y + selectedLift,
                        width: cardSize.width,
                        height: cardSize.height
                    ),
                    order: 400 + (column * 30) + depth,
                    isSelected: id == selectedCardID
                ))
            }
        }

        return items
    }

    private var allCardIDs: [String] {
        Array(cardWindows.keys)
    }

    private var selectedWindow: TerminalCardWindow? {
        guard let selectedCardID else { return nil }
        return cardWindows[selectedCardID]
    }

    private var selectedPlayableSelection: MoveSelection? {
        guard let selectedCardID, let location = cardLocation(for: selectedCardID) else {
            return nil
        }

        switch location {
        case .stock:
            return nil
        case .waste:
            guard wasteIDs.last == selectedCardID, state(for: selectedCardID).isFaceUp else { return nil }
            return MoveSelection(origin: .waste, run: [selectedCardID])
        case .foundation(let suit):
            guard foundationIDs[suit, default: []].last == selectedCardID else { return nil }
            return MoveSelection(origin: .foundation(suit), run: [selectedCardID])
        case .tableau(let column):
            let pile = tableauIDs[column]
            guard let index = pile.firstIndex(of: selectedCardID) else { return nil }
            let run = Array(pile[index...])
            guard !run.isEmpty, run.allSatisfy({ state(for: $0).isFaceUp }) else { return nil }
            return MoveSelection(origin: .tableau(column), run: run)
        }
    }

    private func cardLocation(for id: String) -> CardLocation? {
        if stockIDs.contains(id) { return .stock }
        if wasteIDs.contains(id) { return .waste }
        for suit in DeckCard.Suit.allCases where foundationIDs[suit, default: []].contains(id) {
            return .foundation(suit)
        }
        for (index, pile) in tableauIDs.enumerated() where pile.contains(id) {
            return .tableau(index)
        }
        return nil
    }

    private func remove(run: [String], from origin: CardLocation) {
        switch origin {
        case .stock:
            stockIDs.removeAll { run.contains($0) }
        case .waste:
            wasteIDs.removeAll { run.contains($0) }
        case .foundation(let suit):
            foundationIDs[suit, default: []].removeAll { run.contains($0) }
        case .tableau(let index):
            tableauIDs[index].removeAll { run.contains($0) }
        }
    }

    private func revealTableauTopIfNeeded(afterMovingFrom origin: CardLocation) {
        guard case let .tableau(index) = origin, let top = tableauIDs[index].last else { return }
        if !state(for: top).isFaceUp {
            state(for: top).isFaceUp = true
        }
    }

    private func state(for id: String) -> DeckCardState {
        guard let window = cardWindows[id] else {
            fatalError("Missing card window for \(id)")
        }
        return window.state
    }

    private func bringToFront() {
        backdropWindow?.orderFrontRegardless()
        controlPanel?.orderFrontRegardless()
        cardWindows.values.forEach { $0.orderFrontRegardless() }
        status = "Solitaire table already open."
        syncControlPanel()
    }

    private func activeVisibleFrame() -> CGRect? {
        NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
    }

    private func selectCard(withID id: String) {
        selectedCardID = id
        if let selection = selectedPlayableSelection {
            status = "Selected \(state(for: selection.run[0]).card.shortLabel)."
        } else if let location = cardLocation(for: id), location == .stock {
            drawFromStock()
            return
        } else {
            status = "Selected \(state(for: id).card.shortLabel)."
        }
        layoutSolitaire(animated: true)
        syncControlPanel()
    }

    private func showControlPanel(visibleFrame: CGRect) {
        guard controlPanel == nil else {
            syncControlPanel()
            return
        }

        let panelSize = CGSize(width: 320, height: 300)
        let panelOrigin = CGPoint(
            x: visibleFrame.minX + 24,
            y: visibleFrame.maxY - panelSize.height - 24
        )
        let panel = DeckControlPanelWindow(frame: CGRect(origin: panelOrigin, size: panelSize))
        controlPanel = panel
        syncControlPanel()
        panel.orderFrontRegardless()
    }

    private func syncControlPanel() {
        let selectedLabel = selectedPlayableSelection.map { state(for: $0.run[0]).card.suitLine.capitalized } ?? "None"
        let stockCount = stockIDs.count
        let wasteCount = wasteIDs.count
        let foundationText = DeckCard.Suit.allCases.map { suit in
            let count = foundationIDs[suit, default: []].count
            return "\(suit.pip)\(count)"
        }.joined(separator: "  ")

        controlPanel?.update(
            configuration: .init(
                selectedLabel: selectedLabel,
                status: status,
                stockCount: stockCount,
                wasteCount: wasteCount,
                foundationSummary: foundationText,
                canFlipSelected: canFlipSelectedCard,
                onFlipSelected: { [weak self] in Task { @MainActor in self?.flipSelectedCard() } },
                onStackDeck: { [weak self] in Task { @MainActor in self?.stackDeck() } },
                onShuffleDeck: { [weak self] in Task { @MainActor in self?.startSolitaire() } },
                onDealDeck: { [weak self] in Task { @MainActor in self?.startSolitaire() } },
                onRevealDeck: { [weak self] in Task { @MainActor in self?.revealAllCards() } },
                onDraw: { [weak self] in Task { @MainActor in self?.drawFromStock() } },
                onMoveToFoundation: { [weak self] in Task { @MainActor in self?.moveSelectedToFoundation() } },
                onMoveToTableau: { [weak self] column in Task { @MainActor in self?.moveSelectedToTableau(column) } }
            )
        )
    }

    private var canFlipSelectedCard: Bool {
        guard let selectedCardID, let location = cardLocation(for: selectedCardID) else { return false }
        guard case let .tableau(index) = location else { return false }
        return tableauIDs[index].last == selectedCardID && !state(for: selectedCardID).isFaceUp
    }

    private func checkForWin() {
        let totalFoundations = foundationIDs.values.reduce(0) { $0 + $1.count }
        if totalFoundations == 52 {
            status = "You won."
        }
    }
}

private struct LayoutItem {
    let id: String
    let frame: CGRect
    let order: Int
    let isSelected: Bool
}

private struct MoveSelection {
    let origin: CardLocation
    let run: [String]
}

private enum CardLocation: Equatable {
    case stock
    case waste
    case foundation(DeckCard.Suit)
    case tableau(Int)
}

private final class DeckCardState: ObservableObject, Identifiable {
    let card: DeckCard
    @Published var isFaceUp: Bool

    init(card: DeckCard, isFaceUp: Bool) {
        self.card = card
        self.isFaceUp = isFaceUp
    }

    var id: String { card.id }
}

private final class DeckBackdropWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

private struct DeckControlPanelConfiguration {
    let selectedLabel: String
    let status: String
    let stockCount: Int
    let wasteCount: Int
    let foundationSummary: String
    let canFlipSelected: Bool
    let onFlipSelected: () -> Void
    let onStackDeck: () -> Void
    let onShuffleDeck: () -> Void
    let onDealDeck: () -> Void
    let onRevealDeck: () -> Void
    let onDraw: () -> Void
    let onMoveToFoundation: () -> Void
    let onMoveToTableau: (Int) -> Void
}

private final class DeckControlPanelWindow: NSPanel {
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = "Solitaire Controls"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
    }

    func update(configuration: DeckControlPanelConfiguration) {
        hostingView.rootView = AnyView(DeckControlPanelView(configuration: configuration))
    }
}

private final class TerminalCardWindow: NSWindow {
    let state: DeckCardState
    private let onSelect: (String) -> Void

    init(state: DeckCardState, frame: CGRect, onSelect: @escaping (String) -> Void) {
        self.state = state
        self.onSelect = onSelect
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: TerminalCardView(state: state))
    }

    var cardID: String { state.card.id }
    var cardLabel: String { state.card.suitLine.capitalized }
    var isFaceUp: Bool { state.isFaceUp }

    func setFaceUp(_ faceUp: Bool) {
        state.isFaceUp = faceUp
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onSelect(cardID)
    }
}

private struct DeckControlPanelView: View {
    let configuration: DeckControlPanelConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(configuration.selectedLabel)
                    .font(.headline.monospaced())
                Text("Stock \(configuration.stockCount)   Waste \(configuration.wasteCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(configuration.foundationSummary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Draw", action: configuration.onDraw)
                Button("To Foundation", action: configuration.onMoveToFoundation)
                Button("Flip", action: configuration.onFlipSelected)
                    .disabled(!configuration.canFlipSelected)
            }

            Text("Move To Tableau")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(0..<7, id: \.self) { column in
                    Button("T\(column + 1)") {
                        configuration.onMoveToTableau(column)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("New Deal", action: configuration.onDealDeck)
                Button("Stack", action: configuration.onStackDeck)
                Button("Reveal", action: configuration.onRevealDeck)
            }

            Text(configuration.status)
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
                Text("deck://card")
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
                    colors: [Color(red: 0.12, green: 0.11, blue: 0.1), Color(red: 0.08, green: 0.07, blue: 0.07)],
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
        state.card.suit.isRed ? Color(red: 0.78, green: 0.18, blue: 0.24) : Color(red: 0.12, green: 0.14, blue: 0.18)
    }

    private var faceUpText: String {
        let rank = state.card.rank.rawValue
        let pip = state.card.suit.pip
        let suitName = state.card.suit.rawValue
        return """
        +------------------+
        |\((rank + " " + pip).padding(toLength: 18, withPad: " ", startingAt: 0))|
        |\(suitName.padding(toLength: 18, withPad: " ", startingAt: 0))|
        |                  |
        |       \(padCenter(pip, to: 4))       |
        |      \(padCenter(rank, to: 6))      |
        | SELECT TO MOVE    |
        | FOUNDATION/TAB    |
        |                  |
        |\(padLeft(pip + " " + rank, to: 18))|
        +------------------+
        """
    }

    private var faceDownText: String {
        """
        +------------------+
        |##################|
        |## WINSHUFFLE ###|
        |##################|
        |## SOLITAIRE  ###|
        |## FACE   DOWN ##|
        |## DRAW / MOVE ##|
        |## STACK READY ##|
        |##################|
        +------------------+
        """
    }

    private func padLeft(_ value: String, to width: Int) -> String {
        String(repeating: " ", count: max(width - value.count, 0)) + value
    }

    private func padCenter(_ value: String, to width: Int) -> String {
        let totalPadding = max(width - value.count, 0)
        let leading = totalPadding / 2
        let trailing = totalPadding - leading
        return String(repeating: " ", count: leading) + value + String(repeating: " ", count: trailing)
    }

    private func trafficLight(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 9, height: 9)
    }
}
