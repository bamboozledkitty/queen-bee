import AppKit
import QueenBeeCore
import SwiftUI

/// The panel beside the canvas: the flow's orchestrator, the run log, and what the run produced.
struct SidePanel: View {
    let controller: FlowController
    @Binding var tab: PanelTab
    @Binding var width: Double
    @State private var startWidth: Double?
    @Namespace private var tabs

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(alignment: .leading) { resizeEdge }
    }

    /// The panel's left edge. Drag it to make the panel wider or narrower.
    private var resizeEdge: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let from = startWidth ?? width
                        startWidth = from
                        width = min(760, max(300, from - drag.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .offset(x: -4)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 5) {
                            HStack(spacing: 5) {
                                Text(item.label)
                                    .font(.dsMono(Theme.Size.body, tab == item ? .medium : .regular))
                                if let count = count(for: item) {
                                    Text("\(count)").font(.dsMono(Theme.Size.caption)).foregroundStyle(Theme.inkSecondary.ui)
                                }
                            }
                            // One rule shared by the tabs, so it slides to the tab you pick.
                            ZStack {
                                if tab == item {
                                    Rectangle().fill(Theme.ink.ui).matchedGeometryEffect(id: "rule", in: tabs)
                                }
                            }
                            .frame(height: 2)
                        }
                        .fixedSize()
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.top, Theme.Space.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle((tab == item ? Theme.ink : Theme.inkSecondary).ui)
                }
                Spacer()
                if tab == .orchestrator { orchestratorState }
            }
            .background(Theme.bar.ui)
            .animation(Theme.Motion.standard, value: tab)
            Rectangle().fill(Theme.hairline.ui).frame(height: 1)

            // The orchestrator's terminal stays in place under the other tabs, so switching
            // back to it is instant and it never loses its size.
            ZStack {
                TerminalHost(terminal: controller.orchestrator.view)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Theme.terminal.ui)
                    .opacity(tab == .orchestrator ? 1 : 0)
                    .allowsHitTesting(tab == .orchestrator)
                if tab == .log { LogList(controller: controller) }
                if tab == .output { OutputList(controller: controller) }
            }
        }
    }

    private func count(for tab: PanelTab) -> Int? {
        switch tab {
        case .orchestrator: nil
        case .log: controller.log.isEmpty ? nil : controller.log.count
        case .output: controller.results.isEmpty ? nil : controller.results.count
        }
    }

    @ViewBuilder private var orchestratorState: some View {
        let session = controller.orchestrator
        HStack(spacing: Theme.Space.s) {
            Badge(text: session.state.label.lowercased(), tone: session.state.tone)
            if session.state == .exited || session.state == .notStarted {
                Button(session.state == .exited ? "Restart" : "Start") { controller.startOrchestrator() }
                    .controlSize(.small)
            }
        }
        .padding(.trailing, Theme.Space.m)
    }
}

/// What the runs did, newest at the bottom.
private struct LogList: View {
    let controller: FlowController

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if controller.log.isEmpty {
                        Text("Runs are logged here: each hand-off, each condition's answer, and why a run stopped.")
                            .font(.dsSans(Theme.Size.body))
                            .foregroundStyle(Theme.inkSecondary.ui)
                    }
                    ForEach(controller.log) { line in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(Self.time.string(from: line.date))
                                .foregroundStyle(Theme.inkSecondary.ui)
                            Text(line.text)
                                .foregroundStyle(Theme.ink.ui)
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .font(.dsMono(Theme.Size.caption))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.m)
            }
            .onChange(of: controller.log.count) {
                if let last = controller.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = controller.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .background(Theme.surface.ui)
    }
}

/// Each End card's latest answer, with its saved file when it has one.
private struct OutputList: View {
    let controller: FlowController

    var body: some View {
        let ends = controller.flow.cards.filter { $0.kind == .end }
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if ends.isEmpty {
                    Text("Add an End card to collect a run's final answer here.")
                        .font(.dsSans(Theme.Size.body))
                        .foregroundStyle(Theme.inkSecondary.ui)
                }
                ForEach(ends) { card in
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        HStack {
                            Text(card.name).font(.dsMono(Theme.Size.body, .medium))
                            Spacer()
                            if let file = card.saveTo, !file.isEmpty, controller.results[card.id] != nil {
                                Button(file) {
                                    NSWorkspace.shared.activateFileViewerSelecting([controller.project.root.appendingPathComponent(file)])
                                }
                                .buttonStyle(.link)
                                .font(.dsMono(Theme.Size.caption))
                                .help("Show the saved file in Finder")
                            }
                        }
                        if let text = controller.results[card.id] {
                            Text(text)
                                .font(.dsSans(Theme.Size.title))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Space.m)
                                .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                        } else {
                            Text("Nothing yet. This fills in when a run reaches the card.")
                                .font(.dsSans(Theme.Size.body))
                                .foregroundStyle(Theme.inkSecondary.ui)
                        }
                    }
                    .foregroundStyle(Theme.ink.ui)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.m)
        }
        .background(Theme.surface.ui)
    }
}

/// Puts a session's terminal view into SwiftUI. The view belongs to the session, so this
/// only re-parents it.
struct TerminalHost: NSViewRepresentable {
    let terminal: NSView

    func makeNSView(context: Context) -> NSView {
        let holder = NSView()
        attach(to: holder)
        return holder
    }

    func updateNSView(_ holder: NSView, context: Context) {
        attach(to: holder)
    }

    private func attach(to holder: NSView) {
        guard terminal.superview !== holder else { return }
        holder.subviews.forEach { $0.removeFromSuperview() }
        terminal.frame = holder.bounds
        terminal.autoresizingMask = [.width, .height]
        holder.addSubview(terminal)
    }
}
