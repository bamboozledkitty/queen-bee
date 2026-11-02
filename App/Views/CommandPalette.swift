import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// Everything the flow on screen can do from the keyboard, found by typing: add a card of any kind, run or stop
/// the flow, go to a card by its name, and link the selected card to another by name.
struct CommandPalette: View {
    let controller: FlowController
    let close: () -> Void
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var isFocused: Bool

    private struct Command: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let run: () -> Void
    }

    /// How many commands are listed at once. Typing narrows the rest down.
    private static let shown = 12

    private var commands: [Command] {
        var all: [Command] = []
        let flow = controller.flow
        // Linking comes first while a card is selected: it is what the palette is the only keyboard way to do.
        if case .card(let id) = controller.selection, let from = flow.card(id) {
            let outputs = ports(of: from)
            for target in flow.cards where target.id != id {
                for port in outputs where flow.linkProblem(from: id, port: port, to: target.id) == nil {
                    let by = outputs.count > 1 ? " from \(portLabel(port))" : ""
                    all.append(Command(id: "link/\(port)/\(target.id)", title: "Link \(from.name)\(by) to \(target.name)",
                                       detail: target.kind.label, icon: "arrow.right") { [controller] in
                        controller.link(from: id, port: port, to: target.id)
                    })
                }
            }
        }
        if controller.isRunning {
            all.append(Command(id: "stop", title: "Stop the Run", detail: flow.name, icon: "stop.fill") { [controller] in
                Task { await controller.stop() }
            })
        } else if controller.canRun {
            let starts = controller.startCards
            if starts.count > 1 {
                for start in starts {
                    all.append(Command(id: "run/\(start.id)", title: "Run from \(start.name)", detail: flow.name, icon: "play.fill") { [controller] in
                        Task { await controller.run(startCardID: start.id) }
                    })
                }
            } else {
                all.append(Command(id: "run", title: "Run the Flow", detail: flow.name, icon: "play.fill") { [controller] in
                    Task { await controller.run() }
                })
            }
        }
        for card in flow.cards {
            all.append(Command(id: "go/\(card.id)", title: "Go to \(card.name)", detail: card.kind.label,
                               icon: CanvasGeometry.icon(for: card.kind)) {
                AppServices.shared.reveal(controller, cardID: card.id)
            })
        }
        for kind in CardKindMenu.kinds {
            all.append(Command(id: "add/\(kind.rawValue)", title: "Add \(kind.label) Card", detail: "New card",
                               icon: CanvasGeometry.icon(for: kind)) { [controller] in controller.addCard(kind) })
        }
        all.append(Command(id: "fit", title: "Zoom to Fit", detail: "Canvas", icon: "arrow.up.left.and.arrow.down.right") { [controller] in
            controller.canvas?.zoomToFit()
        })
        all.append(Command(id: "tidy", title: "Tidy Up", detail: "Canvas", icon: "square.grid.2x2") { [controller] in controller.tidy() })
        return all
    }

    var body: some View {
        let found = Array(PaletteSearch.rank(commands, by: query) { $0.title }.prefix(Self.shown))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "command").dsIcon(DS.IconSize.l, .medium).foregroundStyle(Theme.inkSecondary.ui)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .textRole(.subtitle)
                    .focused($isFocused)
                    .onSubmit { if found.indices.contains(picked) { perform(found[picked]) } }
                    .onKeyPress(.downArrow) { picked = min(picked + 1, max(found.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: query) { picked = 0 }
                    .accessibilityLabel("Command")
            }
            .padding(.horizontal, DS.Space.l)
            .frame(height: DS.Size.commandField)

            DSDivider()
            if found.isEmpty {
                Text("Nothing matches. Try a card's name, or \"add\", \"link\" or \"run\".")
                    .textRole(.body)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .padding(DS.Space.m)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, command in
                        HStack(spacing: DS.Space.m) {
                            Image(systemName: command.icon)
                                .dsIcon(DS.IconSize.xl, .medium)
                                .foregroundStyle(Palette.textMuted.color)
                                .frame(width: 18)
                            Text(command.title)
                                .textRole(.label)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s)
                            Text(command.detail)
                                .textRole(.caption)
                                .foregroundStyle(Theme.inkSecondary.ui)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, DS.Space.m)
                        .frame(height: DS.Size.commandRow)
                        .background(index == picked ? Palette.hover.color : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { perform(command) }
                        .onHover { if $0 { picked = index } }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { perform(command) }
                    }
                }
                .padding(DS.Space.s)
            }
            DSDivider()
            HStack(spacing: DS.Space.m) {
                HStack(spacing: DS.Space.xs) { KeyHint("↑", "↓"); Text("Move") }
                HStack(spacing: DS.Space.xs) { KeyHint("↵"); Text("Choose") }
                HStack(spacing: DS.Space.xs) { KeyHint("esc"); Text("Close") }
                Spacer()
            }
            .textRole(.caption)
            .foregroundStyle(Palette.textFaint.color)
            .padding(.horizontal, DS.Space.l)
            .frame(height: DS.Size.commandFooter)
        }
        .foregroundStyle(Theme.ink.ui)
        .frame(width: DS.Size.commandWidth)
        .floatingPanel()
        .dsLift()
        .onAppear { isFocused = true }
    }

    private var placeholder: String {
        if case .card(let id) = controller.selection, let card = controller.flow.card(id) {
            return "Link \(card.name) to…, go to a card, add a card, run"
        }
        return "Add a card, go to a card, run or stop the flow"
    }

    private func perform(_ command: Command) {
        close()
        command.run()
    }
}
