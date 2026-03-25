import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var settings: ShuffleSettings

    var body: some View {
        Form {
            Section("Presets") {
                Picker("Style", selection: $settings.selectedPresetID) {
                    ForEach(settings.presets) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.selectedPresetID) { _, presetID in
                    guard let preset = settings.presets.first(where: { $0.id == presetID }) else {
                        return
                    }
                    settings.applyPreset(preset)
                }

                Text(settings.selectedPreset.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkey") {
                Picker("Key", selection: $settings.hotKeyCode) {
                    ForEach(settings.hotKeyChoices) { choice in
                        Text(choice.label).tag(choice.keyCode)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Command", isOn: $settings.useCommandModifier)
                Toggle("Option", isOn: $settings.useOptionModifier)
                Toggle("Shift", isOn: $settings.useShiftModifier)
                Toggle("Control", isOn: $settings.useControlModifier)

                Text("Current shortcut: \(settings.hotKeyLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Animation") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(settings.animationSpeed, format: .number.precision(.fractionLength(2)))x")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.animationSpeed, in: 0.4...2.4, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shuffle Intensity")
                        Spacer()
                        Text("\(Int(settings.shuffleIntensity * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.shuffleIntensity, in: 0.3...1.5, step: 0.05)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
