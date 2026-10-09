import QueenBeeCore
import SwiftUI

/// Settings for the selected card or link, floating over the canvas's corner.
struct InspectorView: View {
    let controller: FlowController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            case .none:
                EmptyView()
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

private struct CardSettings: View {
    let controller: FlowController
    let card: Card
    @State private var name = ""

    var body: some View {
        HStack {
            Label(card.kind.label, systemImage: CanvasGeometry.icon(for: card.kind))
                .font(.headline)
            Spacer()
            Button(role: .destructive) { controller.deleteSelection() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this card and its links")
        }

        field("Name") {
            TextField("Name", text: $name)
                .onSubmit(commitName)
                .onAppear { name = card.name }
                .onChange(of: card.name) { name = card.name }
        }

        switch card.kind {
        case .agent: agent
        case .start:
            EditorField("Command the run begins with", text: card.command ?? "") { v in patch { $0.command = v } }
        case .ifElse:
            condition
        case .loop:
            condition
            Stepper("Give up after \(card.maxTries ?? 3) tries", value: binding(card.maxTries ?? 3) { v in patch { $0.maxTries = v } }, in: 1...20)
        case .switchCard:
            field("Branches, separated by commas") {
                TextField("bug, feature, question", text: binding((card.branches ?? []).joined(separator: ", ")) { v in
                    let names = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    patch { $0.branches = names }
                })
            }
            hint("Claude picks the branch a message belongs to. Anything else goes out Other.")
        case .prompt:
            EditorField("Rewrite the message as", text: card.template ?? "") { v in patch { $0.template = v } }
            hint("{{message}} is what came in and {{from}} is who sent it. Without {{message}}, the message is added underneath.")
        case .end:
            field("Save the answer to a file") {
                TextField("output/answer.md", text: binding(card.saveTo ?? "") { v in patch { $0.saveTo = v } })
            }
            if let result = controller.results[card.id] {
                field("Latest answer") {
                    ScrollView { Text(result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 160)
                }
            }
        case .and:
            hint("Waits until every card linked into it has replied in this run, then passes their answers on together.")
        case .or:
            hint("Passes on the first reply in a run and drops later ones.")
        case .note:
            EditorField("Note", text: card.text ?? "") { v in patch { $0.text = v } }
        }

        if let warning = controller.warnings[card.id] {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var agent: some View {
        let session = controller.session(forCard: card.id)
        EditorField("Instructions", text: card.instructions ?? "") { v in patch { $0.instructions = v } }
        field("Model") {
            Picker("Model", selection: binding(card.model ?? "") { v in patch { $0.model = v } }) {
                Text("Your default").tag("")
                ForEach(["fable", "opus", "sonnet", "haiku"], id: \.self) { Text($0.capitalized).tag($0) }
                if let custom = card.model, !custom.isEmpty, !["fable", "opus", "sonnet", "haiku"].contains(custom) {
                    Text(custom).tag(custom)
                }
            }
            .labelsHidden()
        }
        field("Effort") {
            Picker("Effort", selection: binding(card.effort ?? "") { v in patch { $0.effort = v } }) {
                Text("Model default").tag("")
                ForEach(["low", "medium", "high", "xhigh", "max"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
        }
        field("Permissions") {
            Picker("Permissions", selection: binding(card.permissionMode ?? "") { v in patch { $0.permissionMode = v } }) {
                Text("Your default").tag("")
                Text("Ask each time").tag("manual")
                Text("Accept edits").tag("acceptEdits")
                Text("Plan only").tag("plan")
                Text("Auto").tag("auto")
            }
            .labelsHidden()
        }
        HStack {
            Circle().fill(Color(nsColor: session.state.color)).frame(width: 8, height: 8)
            Text(session.state.label).font(.callout)
            Spacer()
            Button(session.isLive ? "Restart" : "Start") { controller.startSession(forCard: card.id) }
                .controlSize(.small)
        }
        hint("Instructions, model, effort and permissions take effect when the session restarts.")
    }

    @ViewBuilder private var condition: some View {
        field("Check") {
            Picker("Check", selection: binding(card.check ?? .judge) { v in patch { $0.check = v } }) {
                Text("Claude judges a statement").tag(CheckKind.judge)
                Text("Message contains").tag(CheckKind.contains)
                Text("Message doesn't contain").tag(CheckKind.notContains)
                Text("Message matches a pattern").tag(CheckKind.regex)
            }
            .labelsHidden()
        }
        field((card.check ?? .judge) == .judge ? "Statement, in plain English" : "Text or pattern") {
            TextField((card.check ?? .judge) == .judge ? "The review approves the draft" : "APPROVED",
                      text: binding(card.value ?? "") { v in patch { $0.value = v } }, axis: .vertical)
                .lineLimit(1...4)
        }
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

private struct LinkSettings: View {
    let controller: FlowController
    let link: QueenBeeCore.Link

    var body: some View {
        let from = controller.flow.card(link.from)?.name ?? "?"
        let to = controller.flow.card(link.to)?.name ?? "?"
        HStack {
            Label("Link", systemImage: "arrow.right")
                .font(.headline)
            Spacer()
            Button(role: .destructive) { controller.deleteSelection() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete this link")
        }
        Text(link.port == "out" ? "\(from) → \(to)" : "\(from) · \(portLabel(link.port)) → \(to)")
        Stepper("At most \(link.maxPasses) passes per run",
                value: binding(link.maxPasses) { controller.setMaxPasses(link.id, $0) }, in: 1...50)
        hint("A link stops passing messages once it has fired this many times in one run, so loops always end.")
    }
}

// MARK: Small building blocks

private func binding<T>(_ value: T, set: @escaping (T) -> Void) -> Binding<T> {
    Binding(get: { value }, set: set)
}

private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        content()
    }
}

private func hint(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

/// A multi-line text box that keeps its own draft while you type and writes each change through.
private struct EditorField: View {
    let title: String
    let text: String
    let commit: (String) -> Void
    @State private var draft = ""

    init(_ title: String, text: String, commit: @escaping (String) -> Void) {
        self.title = title
        self.text = text
        self.commit = commit
    }

    var body: some View {
        field(title) {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .frame(minHeight: 70, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .onAppear { draft = text }
                .onChange(of: draft) { if draft != text { commit(draft) } }
                .onChange(of: text) { if text != draft { draft = text } }
        }
    }
}
