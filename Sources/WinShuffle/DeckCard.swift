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

    var accentHex: UInt32 {
        suit.isRed ? 0xC62F3C : 0x1E2430
    }

    static let fullDeck: [DeckCard] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { rank in
            DeckCard(suit: suit, rank: rank)
        }
    }
}
