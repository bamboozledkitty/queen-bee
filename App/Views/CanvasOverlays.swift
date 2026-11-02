import QueenBeeCore
import QueenBeeDesign
import SwiftUI
import UniformTypeIdentifiers

/// The card types, floating at the canvas's corner. Click one to add it at the middle of
/// what's on screen, or drag it to where you want it.
struct PaletteView: View {
    static let width: CGFloat = 132
    let controller: FlowController
    private var services: AppServices { AppServices.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CardKindMenu.kinds, id: \.self) { kind in
                PaletteRow(kind: kind) { controller.addCard(kind) }
                if kind == .agent {
                    // Saved roles sit under Agent: each makes an agent that is already set up.
                    ForEach(services.roles) { role in
                        PaletteRow(kind: .agent, role: role) { controller.addCard(.agent, role: role) }
                            .contextMenu {
                                if role.earlier != nil {
                                    Button("Put Back the Earlier Version") { services.putBackEarlierVersion(of: role.id) }
                                }
                                Button("Delete Role", role: .destructive) { services.deleteRole(role.id) }
                            }
                    }
                    DSDivider().padding(.vertical, DS.Space.xs)
                }
            }
        }
        .padding(DS.Space.xs)
        .frame(width: Self.width)
        .floatingPanel()
    }
}

private struct PaletteRow: View {
    let kind: CardKind
    /// A saved role, when the row stands for one and not for the plain kind.
    var role: AgentRole?
    let add: () -> Void
    @State private var isHovered = false
    /// The pointer has rested on the row long enough to want to know what the card is.
    @State private var showsHelp = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: role == nil ? CanvasGeometry.icon(for: kind) : "person.crop.square")
                .dsIcon(DS.IconSize.m, .medium)
                .frame(width: DS.Size.iconSlot)
                .accessibilityHidden(true)
            Text(role?.name ?? kind.label)
                .textRole(role == nil ? .captionLabel : .caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            // A role a paired device saved or changed, which the Mac asks about before it is first used.
            if let changed = role?.changedLine {
                Image(systemName: "ipad.and.iphone")
                    .dsIcon(DS.IconSize.xs, .medium)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .help(changed)
                    .accessibilityLabel(changed)
            }
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.tight)
        .background(isHovered ? Theme.barHover.ui : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.xs))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .task(id: isHovered) {
            guard isHovered else { return showsHelp = false }
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled { showsHelp = true }
        }
        // Beside the palette, level with the row, and never in the pointer's way.
        .overlay(alignment: .topLeading) {
            if showsHelp {
                CardHelpView(kind: kind, role: role)
                    .offset(x: PaletteView.width + DS.Space.xs)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .zIndex(showsHelp ? 1 : 0)
        .animation(Theme.Motion.standard, value: showsHelp)
        .onTapGesture(perform: add)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(role?.name ?? kind.label)
        .accessibilityHint(role?.changedLine ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Add", add)
        .accessibilityAction(.default, add)
        .onDrag {
            // A type of the app's own, so a terminal under the pointer leaves the drop for the canvas.
            let provider = NSItemProvider()
            let type = CanvasDocumentView.cardKindType.rawValue
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { done in
                done(Data((role.map { "\(kind.rawValue)@\($0.id)" } ?? kind.rawValue).utf8), nil)
                return nil
            }
            return provider
        }
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

/// What a kind of card does, in a sentence anyone can follow, and one small example.
struct CardHelpView: View {
    let kind: CardKind
    var role: AgentRole?

    var body: some View {
        let help = role.map(CardHelp.text(for:)) ?? CardHelp.text(for: kind)
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(spacing: DS.Space.tight) {
                Image(systemName: role == nil ? CanvasGeometry.icon(for: kind) : "person.crop.square").dsIcon(DS.IconSize.m, .medium).accessibilityHidden(true)
                Text(role?.name ?? kind.label).textRole(.label)
            }
            Text(help.what)
                .textRole(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let changed = role?.changedLine {
                Text("\(changed). You're asked before it is first used.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(role == nil ? "For example" : "Its instructions").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
                Text(help.example)
                    .textRole(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: DS.Radius.xs))
            Text("Click to add it, or drag it onto the canvas.")
                .textRole(.caption)
                .foregroundStyle(Theme.inkSecondary.ui)
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(DS.Space.m)
        .frame(width: DS.Size.popoverWidth, alignment: .leading)
        .floatingPanel()
    }
}

enum CardHelp {
    /// A saved role: what it is, and the start of what it tells its agent.
    static func text(for role: AgentRole) -> (what: String, example: String) {
        let settings = [role.model.isEmpty ? nil : role.model.capitalized, role.effort.isEmpty ? nil : "\(role.effort) effort",
                        role.permissionMode.isEmpty ? nil : role.permissionMode].compactMap { $0 }.joined(separator: ", ")
        let brief = role.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return ("A saved role. It adds an agent that is already set up\(settings.isEmpty ? "" : ": \(settings)"). Right-click to delete the role.",
                brief.isEmpty ? "No instructions." : String(brief.prefix(220)) + (brief.count > 220 ? "…" : ""))
    }

    static func text(for kind: CardKind) -> (what: String, example: String) {
        switch kind {
        case .agent:
            ("A live Claude Code agent that does one job. It is given a message, does the work, and its reply goes to whatever it is linked to.",
             "A Writer drafts a slogan, and the draft goes on to a Reviewer.")
        case .start:
            ("Where a run begins. It holds the first message and sends it when you press Run.",
             "“Write a slogan for a neighbourhood bakery.”")
        case .ifElse:
            ("Asks a yes-or-no question about the message. The message goes out Yes or out No.",
             "“Does the review approve the draft?” Yes goes to Done. No goes back to the Writer.")
        case .switchCard:
            ("Sorts each message into one of several branches that you name. Claude reads the message and picks the branch that fits. A message that fits none goes out Other.",
             "With branches bug, feature and question, a crash report goes out bug and reaches the agent that fixes bugs.")
        case .and:
            ("Waits until every card linked into it has answered, then passes all the answers on together.",
             "Three researchers each report back, and one Writer gets all three reports at once.")
        case .or:
            ("Passes on the first answer to arrive and ignores the ones that come after.",
             "Ask two agents the same question and use whichever answers first.")
        case .prompt:
            ("Rewrites the message before it goes on, using a template you write.",
             "“Summarise this in one line: {{message}}” turns a long report into a short brief for the next agent.")
        case .loop:
            ("Sends the work round again until a condition is met, or until it has tried enough times.",
             "Again goes back to the Writer until the review approves, for at most 3 tries. Then Done, or Gave up if it never did.")
        case .approval:
            ("Stops the run and waits for you. You read the message, change it if you like, then approve or reject it.",
             "Before an agent sends an email: Approved goes to the sender, Rejected goes back to the Writer.")
        case .script:
            ("Runs a command on your Mac and checks whether it worked. No AI is involved, so it is quick and certain.",
             "Run “npm test”. Pass goes to Done. Fail goes back to the Coder with the errors.")
        case .forEach:
            ("Splits a list into items and sends them on one at a time. What comes back for each is collected, and when every item is done they all go out Done together.",
             "A list of ten links goes to a Reader one at a time, and the ten summaries go on to a Writer together.")
        case .flow:
            ("Runs another of the project's flows as a single step. Build a piece once, then use it wherever you need it.",
             "A “Review loop” flow of four cards becomes one card in three other flows.")
        case .end:
            ("Where a run's answer lands. It shows the final answer and can save it to a file.",
             "Save the approved slogan to slogan.txt.")
        case .note:
            ("A sticky note for people. Agents never see it.",
             "“Ask Priya before changing the Reviewer's instructions.”")
        }
    }
}

/// Zoom out, the zoom level, zoom in, and fit, pinned to the canvas's corner.
struct ZoomPill: View {
    let controller: FlowController
    @AppStorage("showsMinimap") private var showsMinimap = true

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            button("minus", help: "Zoom out") { controller.canvas?.zoom(by: 0.8) }
            Button { controller.canvas?.zoomToActualSize() } label: {
                Text("\(Int((controller.zoom * 100).rounded()))%")
                    .textRole(.monoCaption)
                    .foregroundStyle(Palette.textMuted.color)
                    .frame(width: 40)
            }
            .buttonStyle(.plain)
            .help("Back to 100%")
            button("plus", help: "Zoom in") { controller.canvas?.zoom(by: 1.25) }
            DSDivider(vertical: true).frame(height: 14).padding(.horizontal, DS.Space.xxs)
            button("arrow.up.left.and.arrow.down.right", help: "Fit the whole flow") { controller.canvas?.zoomToFit() }
            button(showsMinimap ? "map.fill" : "map", help: showsMinimap ? "Hide the map of the flow" : "Show a map of the whole flow") { showsMinimap.toggle() }
        }
        .padding(.horizontal, DS.Space.xs)
        .frame(height: DS.Size.bar)
        .floatingPanel()
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.dsIcon)
            .controlSize(.small)
            .frame(width: 24, height: 24)
            .accessibilityLabel(help)
            .help(help)
    }
}

/// The whole flow in a corner: every card, what is live or waiting, and the part the window
/// is showing. Click or drag in it to go there.
struct Minimap: View {
    static let size = CGSize(width: 190, height: 124)
    let controller: FlowController

    private struct Mark { var rect: CGRect; var failed: Bool; var live: Bool; var waiting: Bool; var selected: Bool; var isAgent: Bool }

    private var marks: [Mark] {
        let flow = controller.flow
        let waiting = Set(controller.cardsNeedingYou.map(\.id))
        let selected = controller.selection.cardIDs
        func isLive(_ card: Card) -> Bool {
            waiting.contains(card.id) || controller.holds.contains { $0.cardID == card.id }
                || (card.kind == .agent && [.working, .needsYou].contains(controller.sessions[card.id]?.state ?? .notStarted))
        }
        // What the map draws: a card each, except that a folded group is the one card it is on the canvas.
        let foldedIDs = Set((flow.groups ?? []).filter(\.isFolded).flatMap(\.cardIDs))
        var marks: [Mark] = flow.cards.filter { !foldedIDs.contains($0.id) }.map { card in
            Mark(rect: CanvasGeometry.frame(of: card), failed: controller.marks[card.id]?.failed == true, live: isLive(card),
                 waiting: waiting.contains(card.id), selected: selected.contains(card.id), isAgent: card.kind == .agent)
        }
        for group in (flow.groups ?? []) where group.isFolded {
            guard let rect = GroupFrameView.frame(of: group, in: flow) else { continue }
            let members = flow.cards.filter { group.cardIDs.contains($0.id) }
            marks.append(Mark(rect: rect, failed: members.contains { controller.marks[$0.id]?.failed == true },
                              live: members.contains(where: isLive), waiting: members.contains { waiting.contains($0.id) },
                              selected: Set(group.cardIDs) == selected, isAgent: false))
        }
        return marks
    }

    var body: some View {
        let marks = self.marks

        let frames = marks.map(\.rect)
        // The map is of the flow, so the cards fill it. The window's view is drawn over them and
        // runs off the map's edge when it takes in more than the flow.
        let world = (frames.isEmpty ? controller.viewport : frames.reduce(CGRect.null) { $0.union($1) }).insetBy(dx: -80, dy: -80)
        let scale = world.isNull || world.width <= 0 ? 1 : min(Self.size.width / world.width, Self.size.height / world.height)
        // The flow is drawn in the middle of the map, whatever its shape.
        let inset = CGSize(width: (Self.size.width - world.width * scale) / 2, height: (Self.size.height - world.height * scale) / 2)

        Canvas { context, _ in
            func place(_ rect: CGRect) -> CGRect {
                CGRect(x: inset.width + (rect.minX - world.minX) * scale, y: inset.height + (rect.minY - world.minY) * scale,
                       width: max(2, rect.width * scale), height: max(2, rect.height * scale))
            }
            for mark in marks {
                let rect = place(mark.rect)
                let fill = mark.failed ? Palette.fail : mark.live ? Palette.live : mark.isAgent ? Palette.textMuted : Palette.textFaint
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(fill.color.opacity(mark.waiting || mark.failed || mark.live ? 1 : 0.55)))
                if mark.selected {
                    context.stroke(Path(rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(Palette.accent.color), lineWidth: 1.5)
                }
            }
            if !controller.viewport.isEmpty {
                context.stroke(Path(roundedRect: place(controller.viewport), cornerRadius: DS.Radius.xs), with: .color(Palette.accent.color), lineWidth: DS.Stroke.hairline)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Palette.panel.color)
        .floatingPanel()
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            guard scale > 0 else { return }
            controller.canvas?.center(on: CGPoint(x: world.minX + (drag.location.x - inset.width) / scale,
                                                  y: world.minY + (drag.location.y - inset.height) / scale))
        })
        .help("The whole flow. Click or drag to go to a part of it.")
    }
}

/// Finds a card by name in any flow and goes to it.
struct FindPanel: View {
    let close: () -> Void
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var isFocused: Bool
    private var services: AppServices { AppServices.shared }

    private struct Match: Identifiable {
        let controller: FlowController
        let card: Card?
        var id: String { "\(ObjectIdentifier(controller))/" + (card?.id ?? "") }
    }

    private var matches: [Match] {
        let wanted = query.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return [] }
        var found: [Match] = []
        // The flow on screen first, then the others.
        let current = services.allFlows.filter { $0 === services.selectedFlow }
        let flows = current + services.allFlows.filter { $0 !== services.selectedFlow }
        for controller in flows {
            if controller.flow.name.localizedCaseInsensitiveContains(wanted) { found.append(Match(controller: controller, card: nil)) }
            for card in controller.flow.cards where card.name.localizedCaseInsensitiveContains(wanted)
                || card.kind.label.localizedCaseInsensitiveContains(wanted) {
                found.append(Match(controller: controller, card: card))
            }
        }
        return Array(found.prefix(12))
    }

    var body: some View {
        let found = matches
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "magnifyingglass").dsIcon(DS.IconSize.l, .medium).foregroundStyle(Theme.inkSecondary.ui).accessibilityHidden(true)
                TextField("Find a card or a flow", text: $query)
                    .textFieldStyle(.plain)
                    .textRole(.subtitle)
                    .focused($isFocused)
                    .onSubmit { if found.indices.contains(picked) { go(to: found[picked]) } }
                    .onKeyPress(.downArrow) { picked = min(picked + 1, max(found.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: query) { picked = 0 }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.snug)

            if !found.isEmpty {
                DSDivider()
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, match in
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: match.card.map { CanvasGeometry.icon(for: $0.kind) } ?? "point.3.connected.trianglepath.dotted")
                                .dsIcon(DS.IconSize.m, .medium)
                                .frame(width: DS.Size.iconSlot)
                                .accessibilityHidden(true)
                            Text(match.card?.name ?? match.controller.flow.name)
                                .textRole(.label)
                                .lineLimit(1)
                            Spacer(minLength: DS.Space.s)
                            Text(match.card == nil ? "flow in \(match.controller.project.name)" : match.controller.flow.name)
                                .textRole(.caption)
                                .foregroundStyle(Theme.inkSecondary.ui)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, DS.Space.s)
                        .padding(.vertical, DS.Space.tight)
                        .background(index == picked ? Theme.barHover.ui : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.xs))
                        .contentShape(Rectangle())
                        .onTapGesture { go(to: match) }
                        .onHover { if $0 { picked = index } }
                    }
                }
                .padding(DS.Space.xs)
            } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                DSDivider()
                Text("No card or flow has that in its name.")
                    .textRole(.body)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .padding(DS.Space.m)
            }
        }
        .foregroundStyle(Theme.ink.ui)
        .frame(width: DS.Size.findWidth)
        .floatingPanel()
        .onAppear { isFocused = true }
    }

    private func go(to match: Match) {
        services.selectedFlow = match.controller
        close()
        guard let card = match.card else { return }
        match.controller.select(.card(card.id))
        // A flow that wasn't on screen needs a moment for its canvas to appear.
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            // A card folded away in a group can't be shown until the group is unfolded.
            if let group = match.controller.flow.group(containing: card.id), group.isFolded { match.controller.setFolded(false, group: group.id) }
            match.controller.canvas?.zoom(toCard: card.id)
        }
    }
}

/// What the flow has cost so far, beside the zoom control: this flow and every sub-flow
/// below it. Click it for where the cost went.
struct CostPill: View {
    let controller: FlowController
    @Binding var showsBreakdown: Bool

    var body: some View {
        let total = controller.usageWithSubflows
        Button { showsBreakdown.toggle() } label: {
            HStack(spacing: DS.Space.tight) {
                Text(total.price)
                    .textRole(.monoCaption)
                    .contentTransition(.numericText())
                if controller.isRunning { StatusDot(.live, size: 5) }
            }
            .foregroundStyle((total.isZero ? Palette.textMuted : Palette.text).color)
            .padding(.horizontal, DS.Space.m)
            .frame(height: DS.Size.bar)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .floatingPanel()
        .help(total.isZero ? "This flow hasn't used anything yet. The figure appears once an agent has replied."
              : "An estimate of what this flow's work has cost so far, sub-flows included. Click to see where it went.")
        .animation(Theme.Motion.standard, value: total.price)
    }
}

/// Where a flow's cost went: its own agents, the sub-flows below it, then run by run.
struct CostBreakdown: View {
    let controller: FlowController
    let close: () -> Void
    private var services: AppServices { AppServices.shared }

    private var sessions: [(name: String, icon: String, usage: Usage)] {
        var rows: [(String, String, Usage)] = []
        if let used = controller.usage[FlowController.orchestratorKey], !used.isZero { rows.append(("Orchestrator", "sparkles", used)) }
        for card in controller.flow.cards where card.kind == .agent {
            if let used = controller.usage[card.id], !used.isZero { rows.append((card.name, "terminal", used)) }
        }
        return rows.sorted { $0.2.cost > $1.2.cost }
    }

    var body: some View {
        let own = controller.totalUsage
        let inner = controller.subflows()
        let total = controller.usageWithSubflows
        // Every bar is a share of the whole, so the eye can compare an agent with a sub-flow.
        let whole = max(total.cost, 0.000001)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cost of \(controller.flow.name)").textRole(.label).lineLimit(1)
                Spacer()
                Text(total.price).textRole(.monoLabel)
                Button(action: close) {
                    Image(systemName: "xmark").dsIcon(DS.IconSize.xs, .semibold).frame(width: DS.Size.iconButton, height: DS.Size.iconButton).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSecondary.ui)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .background(Theme.bar.ui)

            if total.isZero {
                Text("Nothing yet. A figure appears here once an agent in this flow has replied.")
                    .textRole(.body)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .padding(DS.Space.m)
                    .overlay(alignment: .top) { divider }
            }

            if !sessions.isEmpty {
                part(inner.isEmpty ? nil : "This flow's own agents", trailing: inner.isEmpty ? nil : own.price) {
                    ForEach(sessions, id: \.name) { row in
                        line(icon: row.icon, name: row.name, usage: row.usage, share: row.usage.cost / whole)
                    }
                }
            }

            if !inner.isEmpty {
                part("Sub-flows", trailing: inner.reduce(Usage()) { $0 + $1.controller.totalUsage }.price) {
                    ForEach(inner, id: \.controller.flow.id) { entry in
                        Button { open(entry.controller) } label: {
                            line(icon: "arrow.turn.down.right", name: entry.controller.flow.name, usage: entry.controller.totalUsage,
                                 share: entry.controller.totalUsage.cost / whole, indent: CGFloat(entry.depth) * 12, opens: true)
                        }
                        .buttonStyle(.plain)
                        .help("Open \(entry.controller.flow.name) to see its own breakdown")
                    }
                }
            }

            let costed = controller.runs.reversed().filter { $0.usage != nil }.prefix(5)
            if !costed.isEmpty {
                part("Recent runs", trailing: nil) {
                    ForEach(Array(costed)) { run in
                        HStack {
                            Text("\(RunPicker.label(for: run.started)) · \(run.summary)").textRole(.caption)
                            Spacer()
                            Text(run.cost.price).textRole(.monoLabel)
                        }
                    }
                }
            }

            // Inside a sub-flow, the figure above is only this part of something larger.
            if let outer = services.flowTrail.dropLast().last.flatMap({ outer in services.allFlows.first { $0 === outer } }) {
                Button { services.goBack(to: outer) } label: {
                    HStack(spacing: DS.Space.tight) {
                        Image(systemName: "arrow.turn.left.up").dsIcon(DS.IconSize.s, .medium).frame(width: DS.Size.iconSlot).accessibilityHidden(true)
                        Text("Part of \(outer.flow.name)").textRole(.captionLabel).lineLimit(1)
                        Spacer(minLength: DS.Space.s)
                        Text("\(outer.usageWithSubflows.price) in all").textRole(.monoCaption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s)
                .background(Theme.bar.ui)
                .overlay(alignment: .top) { divider }
                .help("Go back to \(outer.flow.name)")
            }

            Text("An estimate of what this work would cost if you paid Anthropic by usage. On a Claude subscription you don't pay this, so read it as a measure of how much the flow uses. It updates each time an agent finishes a reply. A run's figure covers the agents and sub-flows it used, not the orchestrator.")
                .textRole(.caption)
                .foregroundStyle(Theme.inkSecondary.ui)
                .fixedSize(horizontal: false, vertical: true)
                .padding(DS.Space.m)
                .overlay(alignment: .top) { divider }
        }
        .foregroundStyle(Theme.ink.ui)
        .frame(width: DS.Size.menuWidth)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m))
        .floatingPanel()
        .task(id: controller.flow.id) { await controller.refreshUsageWithSubflows() }
    }

    private var divider: some View { DSDivider() }

    /// One titled part of the breakdown, with its subtotal on the right.
    private func part<Content: View>(_ title: String?, trailing: String?, @ViewBuilder rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            if let title {
                HStack {
                    Text(title).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
                    Spacer()
                    if let trailing { Text(trailing).textRole(.caption).foregroundStyle(Theme.inkSecondary.ui) }
                }
            }
            rows()
        }
        .padding(DS.Space.m)
        .overlay(alignment: .top) { divider }
    }

    /// One agent or sub-flow: its name, what it used, and a bar for its share of the whole.
    private func line(icon: String, name: String, usage: Usage, share: Double, indent: CGFloat = 0, opens: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.tight) {
                Image(systemName: icon).dsIcon(DS.IconSize.s, .medium).frame(width: DS.Size.iconSlot).accessibilityHidden(true)
                Text(name).textRole(.captionLabel).lineLimit(1)
                if opens { Image(systemName: "chevron.right").dsIcon(DS.IconSize.xxs, .semibold).foregroundStyle(Theme.inkSecondary.ui).accessibilityHidden(true) }
                Spacer(minLength: DS.Space.s)
                Text(usage.tokenCount).textRole(.monoCaption).foregroundStyle(Theme.inkSecondary.ui)
                Text(usage.price).textRole(.monoLabel).frame(minWidth: 44, alignment: .trailing)
            }
            GeometryReader { space in
                Rectangle().fill(Theme.ink.ui)
                    .frame(width: max(usage.isZero ? 0 : 2, space.size.width * min(1, max(0, share))), height: 2)
            }
            .frame(height: 2)
        }
        .padding(.leading, indent)
        .contentShape(Rectangle())
    }

    /// Goes into a sub-flow and keeps the breakdown open there.
    private func open(_ inner: FlowController) {
        close()
        services.enter(inner, from: controller)
        inner.showsCost = true
    }
}

/// The run's latest step in one line. Click it for the whole log.
struct StatusStrip: View {
    let controller: FlowController
    let showLog: () -> Void

    var body: some View {
        if let last = controller.log.last {
            Button(action: showLog) {
                HStack(spacing: DS.Space.s) {
                    StatusDot(controller.isRunning ? .live : .neutral, size: 6)
                    Text(last.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if controller.handOffs > 0 {
                        Text("\(controller.handOffs) \(controller.handOffs == 1 ? "hand-off" : "hand-offs")")
                            .foregroundStyle(Palette.textMuted.color)
                            .contentTransition(.numericText())
                    }
                }
                .textRole(.caption)
                .foregroundStyle(Palette.text.color)
                .padding(.horizontal, DS.Space.m)
                .frame(height: DS.Size.bar)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .floatingPanel()
            .help("Show everything the run has done")
            .animation(Theme.Motion.standard, value: controller.handOffs)
        }
    }
}

/// A one-line message about something that didn't work. Click to dismiss.
struct BannerView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        Text(text)
            .textRole(.body)
            .foregroundStyle(Palette.failText.color)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .background(Palette.failTint.color, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(Palette.fail.opacity(0.4).color, lineWidth: DS.Stroke.hairline))
            .frame(maxWidth: 520)
            .onTapGesture(perform: dismiss)
            .help("Click to dismiss")
    }
}

/// What an empty flow shows: a short note beside the orchestrator, pointing at it. The
/// orchestrator is where a flow gets described, so the note sends you there and stays out
/// of the canvas's way.
struct OrchestratorCallout: View {
    let controller: FlowController
    /// The orchestrator's terminal is on screen for the arrow to point at.
    let orchestratorIsShowing: Bool
    let showOrchestrator: () -> Void
    @State private var nudged = false

    var body: some View {
        let session = controller.orchestrator
        let isOff = session.state == .notStarted || session.state == .exited
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Describe the flow you want")
                        .textRole(.label)
                    Spacer(minLength: DS.Space.s)
                    Button { AppServices.shared.dismissHint(forFlow: controller.flow.id) } label: {
                        Image(systemName: "xmark").dsIcon(DS.IconSize.xs, .semibold)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .accessibilityLabel("Dismiss")
                    .help("Build it by hand")
                }
                Text(isOff ? "The orchestrator builds it on the canvas, but it isn't running yet."
                           : "Tell the orchestrator and it builds it here. Or drag cards in from the palette.")
                    .textRole(.caption)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
                if isOff {
                    Button("Start the orchestrator") {
                        controller.startOrchestrator()
                        showOrchestrator()
                    }
                    .buttonStyle(.panel())
                    .padding(.top, DS.Space.xs)
                } else if !orchestratorIsShowing {
                    Button("Show the orchestrator", action: showOrchestrator)
                        .buttonStyle(.panel())
                        .padding(.top, DS.Space.xs)
                }
            }
            .foregroundStyle(Theme.ink.ui)
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, DS.Space.s)
            .frame(width: DS.Size.popoverWidth, alignment: .leading)
            .floatingPanel()

            if orchestratorIsShowing, !isOff {
                // The arrow reaches across the gap to the panel, and leans toward it now and then.
                Arrow()
                    .stroke(Theme.ink.ui, style: StrokeStyle(lineWidth: DS.Stroke.link, lineCap: .round, lineJoin: .round))
                    .frame(width: 30, height: 12)
                    .offset(x: nudged ? 4 : 0)
                    .onAppear {
                        guard Theme.Motion.isAllowed else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudged = true }
                    }
            }
        }
    }

    private struct Arrow: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            path.move(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 1))
            return path
        }
    }
}
