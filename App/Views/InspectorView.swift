import QueenBeeCore
import SwiftUI

/// Settings for the selected card or link, floating over the canvas's corner. Every kind of
/// card gets the same three parts: a header that names it, rows for what it is set to, and a
/// footer with what you can do to it.
struct InspectorView: View {
    static let width: CGFloat = 300
    let controller: FlowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch controller.selection {
            case .card(let id):
                if let card = controller.flow.card(id) {
                    CardSettings(controller: controller, card: card)
                        .id(card.id)
                }
            case .link(let id):
                if let link = controller.flow.links.first(where: { $0.id == id }) {
                    LinkSettings(controller: controller, link: link)
                        .id(link.id)
                }
            case .cards(let ids):
                SeveralSettings(controller: controller, count: ids.count)
            case .none:
                EmptyView()
            }
        }
        .frame(width: Self.width)
        .foregroundStyle(Theme.ink.ui)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .floatingPanel()
    }
}

private struct CardSettings: View {
    let controller: FlowController
    let card: Card
    @State private var name = ""

    var body: some View {
        let pending = card.kind == .agent ? controller.settingsAwaitingRestart(forCard: card.id) : []
        VStack(alignment: .leading, spacing: 0) {
            header
            switch card.kind {
            case .agent: agent
            case .start:
                EditorField("Command the run begins with", text: card.command ?? "") { v in patch { $0.command = v } }
            case .ifElse:
                condition
            case .loop:
                condition
                row("Give up after") {
                    HStack(spacing: 4) {
                        StepField(value: card.maxTries ?? 3, range: 1...20) { v in patch { $0.maxTries = v } }
                        Text("tries").font(.dsSans(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                    }
                }
            case .switchCard:
                LineField("Branches, separated by commas", placeholder: "bug, feature, question",
                          text: (card.branches ?? []).joined(separator: ", ")) { v in
                    let names = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    patch { $0.branches = names }
                }
                note("Claude picks the branch a message belongs to. Anything else goes out Other.")
            case .prompt:
                EditorField("Rewrite the message as", text: card.template ?? "") { v in patch { $0.template = v } }
                note("{{message}} is what came in and {{from}} is who sent it. Without {{message}}, the message is added underneath.")
            case .end:
                LineField("Save the answer to a file", placeholder: "output/answer.md", text: card.saveTo ?? "") { v in patch { $0.saveTo = v } }
                if let result = controller.results[card.id] {
                    section {
                        field("Latest answer") {
                            ScrollView {
                                Text(result).font(.dsSans(Theme.Size.body)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                }
            case .and:
                note("Waits until every card linked into it has replied in this run, then passes their answers on together.")
            case .or:
                note("Passes on the first reply in a run and drops later ones.")
            case .note:
                EditorField("Note", text: card.text ?? "") { v in patch { $0.text = v } }
            case .approval:
                LineField("What to check before approving", placeholder: "Is this email right to send?",
                          text: card.text ?? "", lines: 1...3) { v in patch { $0.text = v } }
                if let hold = controller.holds.first(where: { $0.cardID == card.id }) {
                    ApprovalReview(controller: controller, hold: hold)
                        .id(hold.id)
                } else {
                    note("A run stops here and waits for you. You can edit the message, then approve or reject it.")
                }
            case .script:
                EditorField("Command", text: card.command ?? "", mono: true) { v in controller.setScriptCommand(card.id, v) }
                note("Runs in the project folder. The message arrives on standard input and in $QB_MESSAGE. Exit code 0 goes out Pass, anything else Fail, and what the command printed is passed on.")
                if let hold = controller.holds.first(where: { $0.cardID == card.id }) {
                    ScriptReview(controller: controller, hold: hold)
                        .id(hold.id)
                }
            }

            if let warning = controller.warnings[card.id] {
                section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.dsSans(Theme.Size.caption))
                        .foregroundStyle(Theme.failInk.ui)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !pending.isEmpty {
                // The session is still running on what it was started with. Say so beside
                // the buttons that settle it.
                Text("Not applied yet. The running session keeps its old \(Self.list(pending)) until it restarts.")
                    .font(.dsSans(Theme.Size.caption))
                    .foregroundStyle(Theme.liveInk.ui)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, 7)
                    .background(Theme.liveTint.ui)
                    .overlay(alignment: .top) { rule }
                    .transition(.opacity)
            }
            footer(pending: pending)
        }
        .animation(Theme.Motion.standard, value: pending.isEmpty)
    }

    /// The card's kind, its name, and for an agent what its session is doing. The name is
    /// edited where it stands.
    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: CanvasGeometry.icon(for: card.kind))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 16)
                .help(card.kind.label)
            TextField(card.kind.label, text: $name)
                .textFieldStyle(.plain)
                .font(.dsMono(Theme.Size.title, .medium))
                .onSubmit(commitName)
                .onAppear { name = card.name }
                .onChange(of: card.name) { name = card.name }
                .help("Rename this card")
            if card.kind == .agent {
                let session = controller.session(forCard: card.id)
                Badge(text: session.state.label.lowercased(), tone: session.state.tone)
            } else {
                Text(card.kind.label)
                    .font(.dsMono(Theme.Size.caption))
                    .foregroundStyle(Theme.inkSecondary.ui)
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.bar.ui)
    }

    private func footer(pending: [String]) -> some View {
        HStack(spacing: Theme.Space.s) {
            Button { controller.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                .buttonStyle(.panel(.quiet))
                .help("Delete this card and its links")
            Spacer()
            if card.kind == .agent {
                let session = controller.session(forCard: card.id)
                if pending.isEmpty {
                    Button(session.isLive ? "Restart" : "Start") { controller.startSession(forCard: card.id) }
                        .buttonStyle(.panel())
                        .help(session.isLive ? "Restart the session. Its conversation is kept." : "Start the session with these settings")
                } else {
                    Button("Undo") { controller.revertSettings(forCard: card.id) }
                        .buttonStyle(.panel())
                        .help("Put these settings back to what the running session has")
                    Button("Restart to apply") { controller.startSession(forCard: card.id) }
                        .buttonStyle(.panel(.live))
                        .help(session.state == .working ? "Restarting interrupts what the agent is doing now. Its conversation is kept." : "The agent's conversation is kept.")
                }
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 6)
        .background(Theme.bar.ui)
        .overlay(alignment: .top) { rule }
    }

    @ViewBuilder private var agent: some View {
        EditorField("Instructions", text: card.instructions ?? "") { v in patch { $0.instructions = v } }
        row("Model") {
            let known = ["fable", "opus", "sonnet", "haiku"]
            let custom = (card.model ?? "").isEmpty || known.contains(card.model ?? "") ? [] : [(value: card.model ?? "", label: card.model ?? "")]
            MenuField(options: [(value: "", label: "Your default")] + known.map { (value: $0, label: $0.capitalized) } + custom,
                      selection: card.model ?? "") { v in patch { $0.model = v } }
        }
        row("Effort") {
            MenuField(options: [(value: "", label: "Model default")] + ["low", "medium", "high", "xhigh", "max"].map { (value: $0, label: $0) },
                      selection: card.effort ?? "") { v in patch { $0.effort = v } }
        }
        row("Permissions") {
            MenuField(options: [(value: "", label: "Your default"), (value: "manual", label: "Ask each time"),
                                (value: "acceptEdits", label: "Accept edits"), (value: "plan", label: "Plan only"), (value: "auto", label: "Auto")],
                      selection: card.permissionMode ?? "") { v in patch { $0.permissionMode = v } }
        }
    }

    /// "model", "model and effort", "name, model and effort".
    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    @ViewBuilder private var condition: some View {
        let check = card.check ?? .judge
        row("Check") {
            MenuField(options: [(value: CheckKind.judge, label: "Claude judges"), (value: .contains, label: "Contains"),
                                (value: .notContains, label: "Doesn't contain"), (value: .regex, label: "Matches a pattern")],
                      selection: check) { v in patch { $0.check = v } }
        }
        LineField(check == .judge ? "Statement, in plain English" : "Text or pattern",
                  placeholder: check == .judge ? "The review approves the draft" : "APPROVED",
                  text: card.value ?? "", lines: 1...4) { v in patch { $0.value = v } }
    }

    private func commitName() {
        guard name != card.name else { return }
        patch { $0.name = name }
        // A refused name (empty, or already taken) snaps back.
        if controller.flow.card(card.id)?.name != name { name = card.name }
    }

    private func patch(_ change: (inout CardPatch) -> Void) {
        var p = CardPatch()
        change(&p)
        controller.update(card.id, p)
    }
}

/// A message waiting at an Approval card: read it, change it if need be, then send it on or back.
private struct ApprovalReview: View {
    let controller: FlowController
    let hold: PendingHold
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("From \(hold.from). Waiting for you.")
                .font(.dsMono(Theme.Size.caption, .medium))
            TextEditor(text: $draft)
                .font(.dsSans(Theme.Size.body))
                .frame(height: 150)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 3)
                .padding(.vertical, 5)
                .background(Theme.surface.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.live.ui))
                .foregroundStyle(Theme.ink.ui)
            HStack(spacing: Theme.Space.s) {
                Button("Reject") { controller.reject(hold.id) }
                    .buttonStyle(.panel())
                    .help("Send the message out the Rejected output, as it arrived")
                Spacer()
                Button(draft == hold.text ? "Approve" : "Approve edited") { controller.approve(hold.id, text: draft) }
                    .buttonStyle(.panel(.live))
                    .help("Send the message out the Approved output")
            }
        }
        .foregroundStyle(Theme.liveInk.ui)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.liveTint.ui)
        .overlay(alignment: .top) { rule }
        .onAppear { draft = hold.text }
    }
}

/// A Script card whose run is waiting on its command: to be allowed, or to finish.
private struct ScriptReview: View {
    let controller: FlowController
    let hold: PendingHold

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if hold.needsAllow {
                Text("You didn't type this command, so it hasn't run. Read it, then allow it or fail the step.")
                    .font(.dsSans(Theme.Size.caption))
                    .fixedSize(horizontal: false, vertical: true)
                Text(hold.command)
                    .font(.dsMono(Theme.Size.caption))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Theme.surface.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .foregroundStyle(Theme.ink.ui)
                HStack(spacing: Theme.Space.s) {
                    Button("Fail the step") { controller.refuseScript(hold.id) }
                        .buttonStyle(.panel())
                    Spacer()
                    Button("Allow and run") { controller.allowScript(hold.id) }
                        .buttonStyle(.panel(.live))
                        .help("Runs the command now, and lets this card run it in later runs until it changes")
                }
            } else {
                Text("Running its command…")
                    .font(.dsMono(Theme.Size.caption, .medium))
            }
        }
        .foregroundStyle(Theme.liveInk.ui)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.liveTint.ui)
        .overlay(alignment: .top) { rule }
    }
}

/// What can be done to several cards at once.
private struct SeveralSettings: View {
    let controller: FlowController
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "square.on.square.dashed")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text("\(count) cards")
                    .font(.dsMono(Theme.Size.title, .medium))
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.bar.ui)
            note("Drag any of them to move them together, or use the arrow keys. Shift-click a card to add it or take it out.")
            HStack(spacing: Theme.Space.s) {
                Button { controller.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.panel(.quiet))
                Spacer()
                Button("Duplicate") { controller.duplicateSelection() }
                    .buttonStyle(.panel())
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 6)
            .background(Theme.bar.ui)
            .overlay(alignment: .top) { rule }
        }
        .animation(Theme.Motion.quick, value: count)
    }
}

private struct LinkSettings: View {
    let controller: FlowController
    let link: QueenBeeCore.Link

    var body: some View {
        let from = controller.flow.card(link.from)?.name ?? "?"
        let to = controller.flow.card(link.to)?.name ?? "?"
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(link.port == "out" ? "\(from) → \(to)" : "\(from) · \(portLabel(link.port)) → \(to)")
                    .font(.dsMono(Theme.Size.title, .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("Link")
                    .font(.dsMono(Theme.Size.caption))
                    .foregroundStyle(Theme.inkSecondary.ui)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.bar.ui)
            row("Most passes per run") {
                StepField(value: link.maxPasses, range: 1...50) { controller.setMaxPasses(link.id, $0) }
            }
            note("A link stops passing messages once it has fired this many times in one run, so loops always end.")
            HStack {
                Button { controller.deleteSelection() } label: { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.panel(.quiet))
                    .help("Delete this link")
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, 6)
            .background(Theme.bar.ui)
            .overlay(alignment: .top) { rule }
        }
    }
}

// MARK: Small building blocks

/// The hairline between a panel's parts.
private var rule: some View {
    Rectangle().fill(Theme.hairline.ui).frame(height: 1)
}

/// One part of the panel, ruled off from the part above it.
private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    content()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .overlay(alignment: .top) { rule }
}

/// A one-line setting: what it is on the left, its value on the right.
private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(spacing: Theme.Space.s) {
        Text(title).font(.dsSans(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
        Spacer(minLength: Theme.Space.s)
        content()
    }
    .padding(.horizontal, Theme.Space.m)
    .frame(minHeight: 30)
    .overlay(alignment: .top) { rule }
}

private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.dsSans(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
        content()
    }
}

/// A sentence of help under the setting it explains.
private func note(_ text: String) -> some View {
    section {
        Text(text).font(.dsSans(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui).fixedSize(horizontal: false, vertical: true)
    }
}

/// A short text setting that keeps its own draft while you type and writes each change through.
private struct LineField: View {
    let title: String
    let placeholder: String
    let text: String
    var lines: ClosedRange<Int> = 1...1
    let commit: (String) -> Void
    @State private var draft = ""

    init(_ title: String, placeholder: String, text: String, lines: ClosedRange<Int> = 1...1, commit: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.text = text
        self.lines = lines
        self.commit = commit
    }

    var body: some View {
        section {
            field(title) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .lineLimit(lines)
                    .textFieldStyle(.plain)
                    .font(.dsSans(Theme.Size.body))
                    .fieldBox()
                    .onAppear { draft = text }
                    .onChange(of: draft) { if draft != text { commit(draft) } }
                    .onChange(of: text) { if text != draft { draft = text } }
            }
        }
    }
}

/// A multi-line text box that keeps its own draft while you type and writes each change through.
private struct EditorField: View {
    let title: String
    let text: String
    var mono = false
    let commit: (String) -> Void
    @State private var draft = ""

    init(_ title: String, text: String, mono: Bool = false, commit: @escaping (String) -> Void) {
        self.title = title
        self.text = text
        self.mono = mono
        self.commit = commit
    }

    var body: some View {
        section {
            field(title) {
                TextEditor(text: $draft)
                    .font(mono ? .dsMono(Theme.Size.caption) : .dsSans(Theme.Size.body))
                    .frame(height: 84)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 5)
                    .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline.ui))
                    .onAppear { draft = text }
                    .onChange(of: draft) { if draft != text { commit(draft) } }
                    .onChange(of: text) { if text != draft { draft = text } }
            }
        }
    }
}
