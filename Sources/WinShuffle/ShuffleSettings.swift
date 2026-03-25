import AppKit
import Carbon
import Foundation

@MainActor
final class ShuffleSettings: ObservableObject {
    @Published var selectedPresetID: String {
        didSet { defaults.set(selectedPresetID, forKey: Keys.selectedPresetID) }
    }
    @Published var hotKeyCode: UInt32 {
        didSet { defaults.set(Int(hotKeyCode), forKey: Keys.hotKeyCode) }
    }
    @Published var useCommandModifier: Bool {
        didSet { defaults.set(useCommandModifier, forKey: Keys.useCommandModifier) }
    }
    @Published var useOptionModifier: Bool {
        didSet { defaults.set(useOptionModifier, forKey: Keys.useOptionModifier) }
    }
    @Published var useShiftModifier: Bool {
        didSet { defaults.set(useShiftModifier, forKey: Keys.useShiftModifier) }
    }
    @Published var useControlModifier: Bool {
        didSet { defaults.set(useControlModifier, forKey: Keys.useControlModifier) }
    }
    @Published var animationSpeed: Double {
        didSet { defaults.set(animationSpeed, forKey: Keys.animationSpeed) }
    }
    @Published var shuffleIntensity: Double {
        didSet { defaults.set(shuffleIntensity, forKey: Keys.shuffleIntensity) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPresetID = defaults.string(forKey: Keys.selectedPresetID) ?? ShufflePreset.casino.id
        hotKeyCode = UInt32(defaults.object(forKey: Keys.hotKeyCode) as? Int ?? Int(kVK_ANSI_S))
        useCommandModifier = defaults.object(forKey: Keys.useCommandModifier) as? Bool ?? false
        useOptionModifier = defaults.object(forKey: Keys.useOptionModifier) as? Bool ?? true
        useShiftModifier = defaults.object(forKey: Keys.useShiftModifier) as? Bool ?? true
        useControlModifier = defaults.object(forKey: Keys.useControlModifier) as? Bool ?? false
        animationSpeed = defaults.object(forKey: Keys.animationSpeed) as? Double ?? 1.0
        shuffleIntensity = defaults.object(forKey: Keys.shuffleIntensity) as? Double ?? 0.85

        if defaults.object(forKey: Keys.animationSpeed) == nil || defaults.object(forKey: Keys.shuffleIntensity) == nil {
            applyPreset(.casino)
        }
    }

    var hotKey: HotKey {
        HotKey(keyCode: hotKeyCode, modifiers: carbonModifiers)
    }

    var hotKeyLabel: String {
        let labels = [
            useCommandModifier ? "Command" : nil,
            useOptionModifier ? "Option" : nil,
            useShiftModifier ? "Shift" : nil,
            useControlModifier ? "Control" : nil,
            keyDisplayName(for: hotKeyCode)
        ]
        .compactMap { $0 }

        return labels.joined(separator: " + ")
    }

    var animationDuration: Double {
        let base = 1.8
        return max(0.65, base / max(animationSpeed, 0.2))
    }

    var intensityScale: Double {
        max(0.2, shuffleIntensity)
    }

    var presets: [ShufflePreset] {
        [.subtle, .casino, .chaos]
    }

    var selectedPreset: ShufflePreset {
        presets.first(where: { $0.id == selectedPresetID }) ?? .casino
    }

    func applyPreset(_ preset: ShufflePreset) {
        selectedPresetID = preset.id
        animationSpeed = preset.animationSpeed
        shuffleIntensity = preset.shuffleIntensity
    }

    private var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if useCommandModifier { modifiers |= UInt32(cmdKey) }
        if useOptionModifier { modifiers |= UInt32(optionKey) }
        if useShiftModifier { modifiers |= UInt32(shiftKey) }
        if useControlModifier { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private func keyDisplayName(for keyCode: UInt32) -> String {
        hotKeyChoices.first(where: { $0.keyCode == keyCode })?.label ?? "Key \(keyCode)"
    }

    struct KeyChoice: Identifiable, Hashable {
        let keyCode: UInt32
        let label: String
        var id: UInt32 { keyCode }
    }

    let hotKeyChoices: [KeyChoice] = [
        .init(keyCode: UInt32(kVK_ANSI_A), label: "A"),
        .init(keyCode: UInt32(kVK_ANSI_B), label: "B"),
        .init(keyCode: UInt32(kVK_ANSI_C), label: "C"),
        .init(keyCode: UInt32(kVK_ANSI_D), label: "D"),
        .init(keyCode: UInt32(kVK_ANSI_E), label: "E"),
        .init(keyCode: UInt32(kVK_ANSI_F), label: "F"),
        .init(keyCode: UInt32(kVK_ANSI_G), label: "G"),
        .init(keyCode: UInt32(kVK_ANSI_H), label: "H"),
        .init(keyCode: UInt32(kVK_ANSI_I), label: "I"),
        .init(keyCode: UInt32(kVK_ANSI_J), label: "J"),
        .init(keyCode: UInt32(kVK_ANSI_K), label: "K"),
        .init(keyCode: UInt32(kVK_ANSI_L), label: "L"),
        .init(keyCode: UInt32(kVK_ANSI_M), label: "M"),
        .init(keyCode: UInt32(kVK_ANSI_N), label: "N"),
        .init(keyCode: UInt32(kVK_ANSI_O), label: "O"),
        .init(keyCode: UInt32(kVK_ANSI_P), label: "P"),
        .init(keyCode: UInt32(kVK_ANSI_Q), label: "Q"),
        .init(keyCode: UInt32(kVK_ANSI_R), label: "R"),
        .init(keyCode: UInt32(kVK_ANSI_S), label: "S"),
        .init(keyCode: UInt32(kVK_ANSI_T), label: "T"),
        .init(keyCode: UInt32(kVK_ANSI_U), label: "U"),
        .init(keyCode: UInt32(kVK_ANSI_V), label: "V"),
        .init(keyCode: UInt32(kVK_ANSI_W), label: "W"),
        .init(keyCode: UInt32(kVK_ANSI_X), label: "X"),
        .init(keyCode: UInt32(kVK_ANSI_Y), label: "Y"),
        .init(keyCode: UInt32(kVK_ANSI_Z), label: "Z")
    ]

    private enum Keys {
        static let selectedPresetID = "settings.selectedPresetID"
        static let hotKeyCode = "settings.hotKeyCode"
        static let useCommandModifier = "settings.useCommandModifier"
        static let useOptionModifier = "settings.useOptionModifier"
        static let useShiftModifier = "settings.useShiftModifier"
        static let useControlModifier = "settings.useControlModifier"
        static let animationSpeed = "settings.animationSpeed"
        static let shuffleIntensity = "settings.shuffleIntensity"
    }
}

struct HotKey: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

struct ShufflePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let animationSpeed: Double
    let shuffleIntensity: Double
    let motion: ShuffleMotionProfile

    static let subtle = ShufflePreset(
        id: "subtle",
        name: "Subtle",
        summary: "Cleaner motion with less spread and a softer tempo.",
        animationSpeed: 0.82,
        shuffleIntensity: 0.55,
        motion: ShuffleMotionProfile(
            deckOffset: CGPoint(x: -120, y: -80),
            gatherStackStep: CGSize(width: 5, height: -4),
            fanStep: CGSize(width: 18, height: 5),
            fanSweep: CGSize(width: 10, height: 8),
            targetScatter: CGSize(width: 14, height: -10),
            dealArcBase: 26,
            dealArcBonus: 6,
            dealDrift: 6,
            dealStaggerStep: 0.035
        )
    )

    static let casino = ShufflePreset(
        id: "casino",
        name: "Casino",
        summary: "Balanced fan-out with crisp pacing and visible dealing arcs.",
        animationSpeed: 1.12,
        shuffleIntensity: 0.95,
        motion: ShuffleMotionProfile(
            deckOffset: CGPoint(x: -180, y: -110),
            gatherStackStep: CGSize(width: 8, height: -6),
            fanStep: CGSize(width: 28, height: 9),
            fanSweep: CGSize(width: 18, height: 12),
            targetScatter: CGSize(width: 26, height: -18),
            dealArcBase: 42,
            dealArcBonus: 10,
            dealDrift: 12,
            dealStaggerStep: 0.045
        )
    )

    static let chaos = ShufflePreset(
        id: "chaos",
        name: "Chaos",
        summary: "Fast, wide, and dramatic with exaggerated spread and lift.",
        animationSpeed: 1.65,
        shuffleIntensity: 1.4,
        motion: ShuffleMotionProfile(
            deckOffset: CGPoint(x: -250, y: -150),
            gatherStackStep: CGSize(width: 10, height: -8),
            fanStep: CGSize(width: 38, height: 14),
            fanSweep: CGSize(width: 26, height: 18),
            targetScatter: CGSize(width: 40, height: -28),
            dealArcBase: 64,
            dealArcBonus: 16,
            dealDrift: 18,
            dealStaggerStep: 0.06
        )
    )
}

struct ShuffleMotionProfile: Hashable {
    let deckOffset: CGPoint
    let gatherStackStep: CGSize
    let fanStep: CGSize
    let fanSweep: CGSize
    let targetScatter: CGSize
    let dealArcBase: Double
    let dealArcBonus: Double
    let dealDrift: Double
    let dealStaggerStep: Double
}
