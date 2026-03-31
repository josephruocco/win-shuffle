import Foundation

struct DeckCard: Identifiable, Hashable {
    enum Suit: String, CaseIterable {
        case clubs = "CLUBS"
        case diamonds = "DIAMONDS"
        case hearts = "HEARTS"
        case spades = "SPADES"

        var pip: String {
            switch self {
            case .clubs: return "♣"
            case .diamonds: return "♦"
            case .hearts: return "♥"
            case .spades: return "♠"
            }
        }

        var isRed: Bool {
            switch self {
            case .diamonds, .hearts:
                return true
            case .clubs, .spades:
                return false
            }
        }
    }

    enum Rank: String, CaseIterable {
        case ace = "A"
        case two = "2"
        case three = "3"
        case four = "4"
        case five = "5"
        case six = "6"
        case seven = "7"
        case eight = "8"
        case nine = "9"
        case ten = "10"
        case jack = "J"
        case queen = "Q"
        case king = "K"

        var value: Int {
            switch self {
            case .ace: return 1
            case .two: return 2
            case .three: return 3
            case .four: return 4
            case .five: return 5
            case .six: return 6
            case .seven: return 7
            case .eight: return 8
            case .nine: return 9
            case .ten: return 10
            case .jack: return 11
            case .queen: return 12
            case .king: return 13
            }
        }
    }

    let suit: Suit
    let rank: Rank

    var id: String {
        "\(rank.rawValue)\(suit.pip)"
    }

    var terminalTitle: String {
        "card://\(id.lowercased())"
    }

    var suitLine: String {
        "\(rank.rawValue) OF \(suit.rawValue)"
    }

    var shortLabel: String {
        "\(rank.rawValue)\(suit.pip)"
    }

    var accentHex: UInt32 {
        suit.isRed ? 0xC62F3C : 0x1E2430
    }

    static let fullDeck: [DeckCard] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { rank in
            DeckCard(suit: suit, rank: rank)
        }
    }
}
