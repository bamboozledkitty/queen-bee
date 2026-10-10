import QueenBeeCore
import SwiftUI
import UniformTypeIdentifiers

/// The card types, floating at the canvas's corner. Click one to add it at the middle of
/// what's on screen, or drag it to where you want it.
struct PaletteView: View {
    static let width: CGFloat = 132
    let controller: FlowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CardKindMenu.kinds, id: \.self) { kind in
                PaletteRow(kind: kind) { controller.addCard(kind) }
                if kind == .agent {
                    Rectangle().fill(Theme.hairline.ui).frame(height: 1).padding(.vertical, 3)
                }
            }
        }
        .padding(Theme.Space.xs)
        .frame(width: Self.width)
        .floatingPanel()
    }
}

private struct PaletteRow: View {
    let kind: CardKind
    let add: () -> Void
    @State private var isHovered = false
    /// The pointer has rested on the row long enough to want to know what the card is.
    @State private var showsHelp = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: CanvasGeometry.icon(for: kind))
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16)
            Text(kind.label)
                .font(.dsMono(Theme.Size.caption, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 5)
        .background(isHovered ? Theme.barHover.ui : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
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
                CardHelpView(kind: kind)
                    .offset(x: PaletteView.width + Theme.Space.xs)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .offset(x: -6)))
            }
        }
        .zIndex(showsHelp ? 1 : 0)
        .animation(Theme.Motion.standard, value: showsHelp)
        .onTapGesture(perform: add)
        .onDrag {
            // A type of the app's own, so a terminal under the pointer leaves the drop for the canvas.
            let provider = NSItemProvider()
            let type = CanvasDocumentView.cardKindType.rawValue
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { done in
                done(Data(kind.rawValue.utf8), nil)
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

    var body: some View {
        let help = CardHelp.text(for: kind)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: CanvasGeometry.icon(for: kind)).font(.system(size: 11, weight: .medium))
                Text(kind.label).font(.dsMono(Theme.Size.body, .medium))
            }
            Text(help.what)
                .font(.dsSans(Theme.Size.body))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("For example").font(.dsMono(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                Text(help.example)
                    .font(.dsSans(Theme.Size.caption))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
            Text("Click to add it, or drag it onto the canvas.")
                .font(.dsSans(Theme.Size.caption))
                .foregroundStyle(Theme.inkSecondary.ui)
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(Theme.Space.m)
        .frame(width: 250, alignment: .leading)
        .floatingPanel()
    }
}

enum CardHelp {
    static func text(for kind: CardKind) -> (what: String, example: String) {
        switch kind {
        case .agent:
            ("A live Claude Code session that does one job. It is given a message, does the work, and its reply goes to whatever it is linked to.",
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
             "Again goes back to the Writer until the review approves, for at most 3 tries. Then Done.")
        case .approval:
            ("Stops the run and waits for you. You read the message, change it if you like, then approve or reject it.",
             "Before an agent sends an email: Approved goes to the sender, Rejected goes back to the Writer.")
        case .script:
            ("Runs a command on your Mac and checks whether it worked. No AI is involved, so it is quick and certain.",
             "Run “npm test”. Pass goes to Done. Fail goes back to the Coder with the errors.")
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

    var body: some View {
        HStack(spacing: 2) {
            button("minus", help: "Zoom out") { controller.canvas?.zoom(by: 0.8) }
            Button { controller.canvas?.zoomToActualSize() } label: {
                Text("\(Int((controller.zoom * 100).rounded()))%")
                    .font(.dsMono(Theme.Size.caption, .medium))
                    .frame(width: 40)
            }
            .buttonStyle(.plain)
            .help("Back to 100%")
            button("plus", help: "Zoom in") { controller.canvas?.zoom(by: 1.25) }
            Rectangle().fill(Theme.hairline.ui).frame(width: 1, height: 14).padding(.horizontal, 2)
            button("arrow.up.left.and.arrow.down.right", help: "Fit the whole flow") { controller.canvas?.zoomToFit() }
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .floatingPanel()
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// What the flow has cost so far, beside the zoom control. Click it for where the cost went.
struct CostPill: View {
    let controller: FlowController
    @Binding var showsBreakdown: Bool

    var body: some View {
        let total = controller.totalUsage
        if !total.isZero {
            Button { showsBreakdown.toggle() } label: {
                HStack(spacing: 5) {
                    Text(total.price)
                        .font(.dsMono(Theme.Size.caption, .medium))
                        .contentTransition(.numericText())
                    if controller.isRunning {
                        Circle().fill(Theme.live.ui).frame(width: 5, height: 5)
                    }
                }
                .foregroundStyle(Theme.ink.ui)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .floatingPanel()
            .help("What this flow has used so far, at API prices. Click for the breakdown.")
            .animation(Theme.Motion.standard, value: total.price)
        }
    }
}

/// Where a flow's cost went: by session, then by run.
struct CostBreakdown: View {
    let controller: FlowController
    let close: () -> Void

    private var sessions: [(name: String, icon: String, usage: Usage)] {
        var rows: [(String, String, Usage)] = []
        if let used = controller.usage[FlowController.orchestratorKey], !used.isZero { rows.append(("Orchestrator", "sparkles", used)) }
        for card in controller.flow.cards where card.kind == .agent {
            if let used = controller.usage[card.id], !used.isZero { rows.append((card.name, "terminal", used)) }
        }
        return rows.sorted { $0.2.cost > $1.2.cost }
    }

    var body: some View {
        let total = controller.totalUsage
        let top = sessions.first?.usage.cost ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cost of this flow").font(.dsMono(Theme.Size.title, .medium))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSecondary.ui)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.bar.ui)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(sessions, id: \.name) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: row.icon).font(.system(size: 10, weight: .medium)).frame(width: 14)
                            Text(row.name).font(.dsMono(Theme.Size.caption, .medium)).lineLimit(1)
                            Spacer(minLength: Theme.Space.s)
                            Text(row.usage.tokenCount).font(.dsMono(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                            Text(row.usage.price).font(.dsMono(Theme.Size.caption, .medium)).frame(minWidth: 44, alignment: .trailing)
                        }
                        // The bar is this session's share of the most expensive one.
                        GeometryReader { space in
                            Rectangle().fill(Theme.ink.ui)
                                .frame(width: max(2, space.size.width * (top > 0 ? row.usage.cost / top : 0)), height: 2)
                        }
                        .frame(height: 2)
                    }
                }
                HStack {
                    Text("In all").font(.dsMono(Theme.Size.caption, .medium))
                    Spacer()
                    Text(total.tokenCount).font(.dsMono(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                    Text(total.price).font(.dsMono(Theme.Size.caption, .medium)).frame(minWidth: 44, alignment: .trailing)
                }
                .padding(.top, 4)
            }
            .padding(Theme.Space.m)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.ui).frame(height: 1) }

            let costed = controller.runs.reversed().filter { $0.usage != nil }.prefix(5)
            if !costed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent runs").font(.dsSans(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                    ForEach(Array(costed)) { run in
                        HStack {
                            Text("\(RunPicker.label(for: run.started)) · \(run.outcome.rawValue)").font(.dsMono(Theme.Size.caption))
                            Spacer()
                            Text(run.cost.price).font(.dsMono(Theme.Size.caption, .medium))
                        }
                    }
                }
                .padding(Theme.Space.m)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.ui).frame(height: 1) }
            }

            Text("Worked out by Claude Code at API prices. On a Claude plan you aren't billed per token, so read it as a measure of how much the flow uses. A run's figure leaves out the orchestrator.")
                .font(.dsSans(Theme.Size.caption))
                .foregroundStyle(Theme.inkSecondary.ui)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Space.m)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.ui).frame(height: 1) }
        }
        .foregroundStyle(Theme.ink.ui)
        .frame(width: 300)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .floatingPanel()
        .task { await controller.refreshUsage() }
    }
}

/// The run's latest step in one line. Click it for the whole log.
struct StatusStrip: View {
    let controller: FlowController
    let showLog: () -> Void

    var body: some View {
        if let last = controller.log.last {
            Button(action: showLog) {
                HStack(spacing: Theme.Space.s) {
                    Circle()
                        .fill((controller.isRunning ? Theme.live : Theme.inkSecondary).ui)
                        .frame(width: 6, height: 6)
                    Text(last.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if controller.handOffs > 0 {
                        Text("\(controller.handOffs) hand-offs")
                            .foregroundStyle(Theme.inkSecondary.ui)
                            .contentTransition(.numericText())
                    }
                }
                .font(.dsMono(Theme.Size.caption))
                .foregroundStyle(Theme.ink.ui)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 5)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .floatingPanel()
            .help("Show the run log")
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
            .font(.dsSans(Theme.Size.body))
            .foregroundStyle(Theme.failInk.ui)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 6)
            .background(Theme.failTint.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.failInk.ui, lineWidth: Theme.Stroke.card))
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Describe the flow you want")
                        .font(.dsMono(Theme.Size.body, .medium))
                    Spacer(minLength: Theme.Space.s)
                    Button { AppServices.shared.dismissHint(forFlow: controller.flow.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .help("Build it by hand")
                }
                Text(isOff ? "The orchestrator builds it on the canvas, but its session isn't running."
                           : "Tell the orchestrator and it builds it here. Or drag cards in from the palette.")
                    .font(.dsSans(Theme.Size.caption))
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
                if isOff {
                    Button("Start the orchestrator") {
                        controller.startOrchestrator()
                        showOrchestrator()
                    }
                    .buttonStyle(.panel())
                    .padding(.top, 3)
                } else if !orchestratorIsShowing {
                    Button("Show the orchestrator", action: showOrchestrator)
                        .buttonStyle(.panel())
                        .padding(.top, 3)
                }
            }
            .foregroundStyle(Theme.ink.ui)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 9)
            .frame(width: 250, alignment: .leading)
            .floatingPanel()

            if orchestratorIsShowing, !isOff {
                // The arrow reaches across the gap to the panel, and leans toward it now and then.
                Arrow()
                    .stroke(Theme.ink.ui, style: StrokeStyle(lineWidth: Theme.Stroke.link, lineCap: .round, lineJoin: .round))
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
