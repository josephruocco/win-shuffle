import AppKit
import Carbon
import Foundation

@MainActor
final class ShuffleSettings: ObservableObject {
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
        hotKeyCode = UInt32(defaults.object(forKey: Keys.hotKeyCode) as? Int ?? Int(kVK_ANSI_S))
        useCommandModifier = defaults.object(forKey: Keys.useCommandModifier) as? Bool ?? false
        useOptionModifier = defaults.object(forKey: Keys.useOptionModifier) as? Bool ?? true
        useShiftModifier = defaults.object(forKey: Keys.useShiftModifier) as? Bool ?? true
        useControlModifier = defaults.object(forKey: Keys.useControlModifier) as? Bool ?? false
        animationSpeed = defaults.object(forKey: Keys.animationSpeed) as? Double ?? 1.0
        shuffleIntensity = defaults.object(forKey: Keys.shuffleIntensity) as? Double ?? 0.85
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
