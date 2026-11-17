import SwiftUI

/// Settings — hotkey, model and cleanup. Opens on ⌘, via the standard `Settings` scene,
/// so the system wires up the menu item and the shortcut.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        Form {
            Section {
                Picker("Push-to-talk key", selection: Binding(
                    get: { settings.pushToTalkKey },
                    set: { key in
                        settings.pushToTalkKey = key
                        controller.reloadHotkey()
                    }
                )) {
                    ForEach(PushToTalkKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                if settings.pushToTalkKey == .fn {
                    if !SystemKeyboard.fnKeyDoesNothing {
                        warning("Set System Settings ▸ Keyboard ▸ “Press 🌐 key to” to Do "
                            + "Nothing, or every press also triggers it.")
                    }
                    if SystemKeyboard.appleDictationEnabled {
                        warning("Apple Dictation is on. If its shortcut is “Press 🌐 "
                            + "Twice”, change it, or double-tap starts both.")
                    }
                    if !SystemKeyboard.fnKeyDoesNothing || SystemKeyboard.appleDictationEnabled {
                        Button("Open Keyboard Settings…") { SystemKeyboard.openKeyboardSettings() }
                    }
                }
            } header: {
                Text("Push to talk")
            } footer: {
                note("Hold to dictate; release to type. Double-tap for hands-free — tap again to "
                    + "finish, Esc to cancel.")
            }

            Section {
                LabeledContent("Speech model", value: "Parakeet, on device")
            } header: {
                Text("Model")
            } footer: {
                note("Runs on the Neural Engine. Text lands when you release the key; the ~470 MB "
                    + "model downloads once.")
            }

            Section {
                Toggle("Clean up transcripts", isOn: $settings.cleanupEnabled)
            } header: {
                Text("Cleanup")
            } footer: {
                note("Strips fillers, fixes spacing and punctuation. The dictionary's corrections "
                    + "run either way.")
            }
        }
        .formStyle(.grouped)
        .frame(width: DS.Size.settingsWidth, height: DS.Size.settingsHeight)
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Color.caution)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
