import SwiftUI

/// The app's few settings: how it looks, what new agents run on, and where Claude Code is.
struct SettingsView: View {
    @AppStorage(Theme.modeKey) private var mode = Theme.Mode.system.rawValue
    @AppStorage("defaultModel") private var defaultModel = ""
    @AppStorage(Notifier.settingKey) private var notifies = true
    @AppStorage("subflowDepth") private var subflowDepth = 3
    private var services: AppServices { AppServices.shared }

    var body: some View {
        Form {
            Picker("Appearance", selection: $mode) {
                ForEach(Theme.Mode.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: mode) { Theme.apply(Theme.Mode(rawValue: mode) ?? .system) }

            Picker("New agents run on", selection: $defaultModel) {
                Text("Your Claude Code default").tag("")
                ForEach(["fable", "opus", "sonnet", "haiku"], id: \.self) { Text($0.capitalized).tag($0) }
            }

            Toggle("Notify me when a card needs me or a run ends", isOn: $notifies)

            Stepper(value: $subflowDepth, in: 1...6) {
                Text("Sub-flows can go \(subflowDepth) \(subflowDepth == 1 ? "level" : "levels") deep")
                Text("A Flow card runs another flow, which can have Flow cards of its own. This is how far down that can go. A run never goes deeper, whatever a flow's file says.")
            }

            LabeledContent("Claude Code") {
                if let claude = services.environment?.claude {
                    Text(claude).font(.dsMono(Theme.Size.caption)).textSelection(.enabled)
                } else if services.environment == nil {
                    Text("Looking…").foregroundStyle(.secondary)
                } else {
                    Text("Not found. Install Claude Code, then reopen Queen Bee.").foregroundStyle(Theme.failInk.ui)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
