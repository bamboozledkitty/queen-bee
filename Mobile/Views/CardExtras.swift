import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// The parts of a card's details that are buttons more than settings, as the Mac's settings panel has them: a
/// schedule turned on or off, a role saved, brought up to date, put back or deleted, and a sub-flow made or gone
/// into. Each sends one command, and waits for the Mac's answer before it can be pressed again.

/// "Turn on" or "Turn off" for a Start card's schedule. The lines above it say whether it is on and when it next runs.
/// "Turn on" asks first, as the Mac's Schedules do, with the command and the schedule it will run on. What it showed
/// goes to the Mac with the command: if the card has changed since, nothing is turned on and it asks again. What to
/// ask and when is `ScheduleQuestion`'s.
struct ScheduleSwitch: View {
    @Environment(RemoteClient.self) private var client
    let cardID: String
    let isOn: Bool
    @State private var question = ScheduleQuestion()

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(isOn ? "Runs by itself while it is on." : "Turned on here, it runs by itself, with nobody watching.")
                .textRole(.caption)
                .foregroundStyle(Theme.inkSecondary.ui)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            Button(isOn ? "Turn off" : "Turn on") {
                if isOn { Task { await client.armSchedule(cardID, on: false) } } else { question.ask(current, fingerprint: fingerprint) }
            }
            .buttonStyle(.panel(isOn ? .outline : .live))
            .fixedSize()
            .disabled(client.mirror.snapshot == nil || client.isArming(cardID))
            .accessibilityHint(isOn ? "Turns the schedule off on your Mac. It stays set, to turn on again."
                                    : "Asks first, then turns the schedule on on your Mac, for the flow as it is now.")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: Theme.Touch.target)
        .confirmationDialog("Turn on this schedule?", isPresented: Binding(get: { question.open != nil }, set: { if !$0 { question.close() } }),
                            titleVisibility: .visible, presenting: question.open) { shown in
            Button("Turn on") { Task { await turnOn(shown) } }
            Button("Cancel", role: .cancel) {}
        } message: { shown in
            Text(shown.card.trigger.map {
                ScheduleShown.consequence(of: shown.card, trigger: $0, flow: client.mirror.snapshot?.flow.name ?? "The flow",
                                          onDevice: true, macChecks: client.mirror.macChecksSchedules)
            } ?? "")
        }
        .onChange(of: question.open == nil) { askAgain() }
        .onDisappear { question = ScheduleQuestion() }
    }

    /// The card as this device has it now.
    private var current: Card? { client.mirror.snapshot?.flow.card(cardID) }
    /// The fingerprint the Mac sent with it.
    private var fingerprint: String? { client.scheduleFingerprint(cardID) }

    private func turnOn(_ shown: ScheduleQuestion.Shown) async {
        guard question.turnOn(shown, now: current) else { return askAgain() }
        guard await client.armSchedule(cardID, on: true, shown: shown.fingerprint) != nil else { return }
        question.refused(shown, now: current, fingerprint: fingerprint)
        askAgain()
    }

    /// On the next turn, so the question isn't lost in the closing of the one before.
    private func askAgain() {
        Task { @MainActor in _ = question.askAgain(now: current, fingerprint: fingerprint) }
    }
}

/// A Flow card's way into the flow it runs.
struct SubflowRow: View {
    @Environment(RemoteClient.self) private var client
    let cardID: String
    let inner: RemoteFlowSummary

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text("Runs \(inner.name).").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
            Spacer(minLength: Theme.Space.s)
            Button("Open") { client.openSubflow(of: cardID) }
                .buttonStyle(.panel())
                .fixedSize()
                .accessibilityLabel("Open \(inner.name)")
                .accessibilityHint("Shows the flow this card runs on the canvas. Back to this flow is over the canvas there.")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: Theme.Touch.target)
    }
}

/// A Flow card that runs nothing yet: the Mac's "New sub-flow", which asks the new flow's name first.
struct NewSubflowRow: View {
    @Environment(RemoteClient.self) private var client
    let cardID: String

    var body: some View {
        let busy = client.mirror.waiting.values.contains { if case .newSubflow(_, cardID, _) = $0 { true } else { false } }
        HStack(spacing: Theme.Space.s) {
            Text("Make a sub-flow just for this card:").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
            Spacer(minLength: Theme.Space.s)
            Button("New sub-flow") { client.askForNewSubflow(for: cardID) }
                .buttonStyle(.panel(.filled))
                .fixedSize()
                .disabled(busy)
                .accessibilityHint("Asks for a name, then makes a flow with an Input and an Output on your Mac for this card to run.")
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .frame(minHeight: Theme.Touch.target)
    }
}

/// The Mac's line under an agent's role when the card has drifted from it, with its two ways back together.
struct RoleDriftRow: View {
    @Environment(RemoteClient.self) private var client
    let cardID: String

    var body: some View {
        let reset = client.resetCommand(cardID), update = client.updateRoleCommand(cardID)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.s) {
                line
                Spacer(minLength: Theme.Space.s)
                buttons(reset: reset, update: update)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                line
                HStack(spacing: Theme.Space.s) {
                    Spacer(minLength: 0)
                    buttons(reset: reset, update: update)
                }
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    private var line: some View {
        Text(EditForm.roleDrift).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func buttons(reset: RemoteCommand?, update: RemoteCommand?) -> some View {
        Button("Reset") { Task { await client.resetRole(cardID) } }
            .buttonStyle(.panel(.quiet))
            .fixedSize()
            .disabled(reset.map(client.isSending) ?? true)
            .accessibilityHint("Puts this card back to what the role holds.")
        Button("Update role") { Task { await client.updateRole(from: cardID) } }
            .buttonStyle(.panel())
            .fixedSize()
            .disabled(update.map(client.isSending) ?? true)
            .accessibilityHint("Saves this card's settings into the role. Other agents with the role take them when Reset is chosen on them.")
    }
}

/// An agent's role, as the Mac's menu has it: the roles to pick from, or None, then "Save as a New Role…" for a card
/// with no role, or "Update “X” from This Card" for one that has one, and the way to delete that role.
struct RoleMenu: View {
    @Environment(RemoteClient.self) private var client
    let field: EditField
    let choices: [EditField.Choice]

    var body: some View {
        let picked = client.shown(field).text
        let cardID: String? = if case .card(let id) = field.key.item { id } else { nil }
        let role = (client.mirror.library?.roles ?? []).first { $0.id == picked && !picked.isEmpty }
        let chosen = choices.first { $0.value == picked }?.label ?? (picked.isEmpty ? "None" : picked)
        Menu {
            Picker("Role", selection: Binding { picked } set: { new in Task { await client.setField(field.key, .text(new)) } }) {
                ForEach(choices, id: \.value) { Text($0.label).tag($0.value) }
            }
            if let cardID {
                Divider()
                if let role {
                    Button("Update “\(role.name)” from This Card") { Task { await client.updateRole(from: cardID) } }
                    Button("Delete “\(role.name)”…", role: .destructive) { client.askToDeleteRole(role.id) }
                } else {
                    Button("Save as a New Role…") { client.askToSaveRole(from: cardID) }
                }
            }
        } label: {
            HStack(spacing: DS.Space.tight) {
                Text(chosen).textRole(.label).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").dsIcon(DS.IconSize.s, .semibold).foregroundStyle(Theme.inkSecondary.ui)
            }
            .foregroundStyle(Theme.ink.ui)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: DS.Size.rowCompact)
            .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline.ui))
            .frame(minHeight: Theme.Touch.target)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Role")
        .accessibilityValue(chosen)
        .accessibilityHint("Picks a saved role, or saves this card as one.")
    }
}
