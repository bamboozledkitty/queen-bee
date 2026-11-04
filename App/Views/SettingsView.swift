import QueenBeeDesign
import SwiftUI

/// The app's few settings: how it looks, what new agents run on, and where Claude Code is.
struct SettingsView: View {
    @AppStorage(Theme.modeKey) private var mode = Theme.Mode.system.rawValue
    @AppStorage("defaultModel") private var defaultModel = ""
    @AppStorage(Notifier.settingKey) private var notifies = true

    private var services: AppServices { AppServices.shared }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $mode) {
                    ForEach(Theme.Mode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: mode) { Theme.apply(Theme.Mode(rawValue: mode) ?? .system) }

                Picker("New agents run on", selection: $defaultModel) {
                    Text("Your Claude Code default").tag("")
                    ForEach(["fable", "opus", "sonnet", "haiku"], id: \.self) { Text($0.capitalized).tag($0) }
                }

                Toggle("Notify me when a card needs me or a run ends", isOn: $notifies)
            } header: {
                heading("General")
            }

            Section {
                LabeledContent("Claude Code") {
                    if let claude = services.environment?.claude {
                        Text(claude).textRole(.monoCaption).foregroundStyle(Palette.textMuted.color).textSelection(.enabled)
                    } else if services.environment == nil {
                        Text("Looking…").foregroundStyle(Palette.textMuted.color)
                    } else {
                        Text("Not found. Install Claude Code, then reopen Queen Bee.").foregroundStyle(Palette.failText.color)
                    }
                }
            } header: {
                heading("Claude Code")
            }

            RemoteSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .textRole(.body)
        .foregroundStyle(Palette.text.color)
        .tint(Palette.accent.color)
        .background(Palette.panel.color)
        .frame(width: DS.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func heading(_ title: String) -> some View {
        Text(title).textRole(.sectionHeader).foregroundStyle(Palette.textFaint.color)
    }
}
