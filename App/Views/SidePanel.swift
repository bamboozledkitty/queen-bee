import AppKit
import QueenBeeCore
import QueenBeeDesign
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
                        VStack(spacing: DS.Space.tight) {
                            HStack(spacing: DS.Space.tight) {
                                Text(item.label)
                                    .textRole(tab == item ? .label : .body)
                                if let count = count(for: item) {
                                    Text("\(count)").textRole(.caption).foregroundStyle(Theme.inkSecondary.ui)
                                }
                            }
                            // One rule shared by the tabs, so it slides to the tab you pick.
                            ZStack {
                                if tab == item {
                                    Rectangle().fill(Theme.select.ui).matchedGeometryEffect(id: "rule", in: tabs)
                                }
                            }
                            .frame(height: 2)
                        }
                        .fixedSize()
                        .padding(.horizontal, DS.Space.m)
                        .padding(.top, DS.Space.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle((tab == item ? Theme.ink : Theme.inkSecondary).ui)
                }
                Spacer()
                if tab == .orchestrator { orchestratorState }
                if tab == .log, !controller.runs.isEmpty {
                    RunPicker(controller: controller)
                }
                if tab == .log, !controller.log.isEmpty {
                    Button("Clear") { controller.clearLog() }
                        .buttonStyle(.panel(.quiet))
                        .padding(.trailing, DS.Space.s)
                        .help("Clear the log and the list of earlier runs, but for the runs you keep")
                }
            }
            .frame(minHeight: DS.Size.tabRow - 4)
            .animation(Theme.Motion.standard, value: tab)
            DSDivider()
            if let id = controller.viewedRunID, let run = controller.runs.first(where: { $0.id == id }) {
                // The canvas is showing an earlier run. Say so, with the way back.
                HStack(spacing: DS.Space.s) {
                    Text("Showing \(run.number.map { "run \($0)" } ?? "the run") from \(RunPicker.label(for: run.started)).")
                        .textRole(.caption)
                    Spacer()
                    Button("Back to latest") { controller.view(run: nil) }
                        .buttonStyle(.panel())
                }
                .foregroundStyle(Theme.ink.ui)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.tight)
                .background(Theme.barHover.ui)
                DSDivider()
            }

            // The orchestrator's terminal stays in place under the other tabs, so switching
            // back to it is instant and it never loses its size.
            ZStack {
                TerminalHost(terminal: controller.orchestrator.view)
                    .padding(.horizontal, DS.Space.tight)
                    .padding(.vertical, DS.Space.xs)
                    .background(Theme.Canvas.terminal.ui)
                    .opacity(tab == .orchestrator ? 1 : 0)
                    .allowsHitTesting(tab == .orchestrator)
                if tab == .log { LogList(controller: controller) }
                if tab == .output { OutputList(controller: controller) }
            }
            // The terminal stays inside its own area, below the banner above, and never draws up over it.
            .clipped()
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
        HStack(spacing: DS.Space.s) {
            Badge(text: session.state.label.lowercased(), tone: session.state.tone)
            if session.state == .exited || session.state == .notStarted {
                Button(session.state == .exited ? "Restart" : "Start") { controller.startOrchestrator() }
                    .controlSize(.small)
            } else if controller.orchestratorNeedsRestart {
                Button("Restart to apply") { controller.startOrchestrator() }
                    .controlSize(.small)
                    .help("This flow was renamed or moved since the orchestrator started, and it still goes by the old details. It keeps its conversation so far.")
            } else {
                Button { controller.startOrchestrator() } label: {
                    Image(systemName: "arrow.clockwise").dsIcon(DS.IconSize.s, .medium).frame(width: DS.Size.iconButton, height: DS.Size.iconButton).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSecondary.ui)
                .accessibilityLabel("Restart orchestrator")
                .help(session.state == .working ? "Restart the orchestrator. This interrupts what it is doing now. It keeps its conversation so far."
                                                : "Restart the orchestrator. It keeps its conversation so far and reads the app's capabilities again.")
            }
        }
        .padding(.trailing, DS.Space.m)
    }
}

/// Picks which run the canvas and the log show: the latest, or an earlier one.
struct RunPicker: View {
    let controller: FlowController

    static func label(for date: Date) -> String {
        // The system's own time format (12 or 24 hour), with a short date when it isn't today.
        RunClock.moment(date)
    }

    var body: some View {
        Menu {
            ForEach(controller.runs.reversed()) { run in
                let isShown = controller.viewedRunID == run.id || (controller.viewedRunID == nil && run.id == controller.runs.last?.id)
                Toggle(isOn: Binding(get: { isShown }, set: { _ in controller.view(run: run.id) })) {
                    Text("\(run.number.map { "Run \($0) · " } ?? "")\(Self.label(for: run.started)) · \(run.summary) · \(run.handOffs) \(run.handOffs == 1 ? "hand-off" : "hand-offs")\(run.isKept ? " · Kept" : "")\(run.isRehearsal ? " · Rehearsal" : "")")
                    Text(run.command)
                }
            }
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text(controller.viewedRunID == nil ? "Latest run" : "Earlier run")
                Image(systemName: "chevron.up.chevron.down").dsIcon(DS.IconSize.xxs, .semibold).accessibilityHidden(true)
            }
            .textRole(.captionLabel)
            .foregroundStyle(Theme.inkSecondary.ui)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(controller.isRunning)
        .padding(.trailing, DS.Space.s)
        .help(controller.isRunning ? "Earlier runs can be looked at once this one ends" : "Show an earlier run on the canvas and in the log")
    }
}

/// What the runs did, newest at the bottom.
private struct LogList: View {
    let controller: FlowController
    /// The log is scrolled to its end, so new lines keep it there. Scrolled up to read, it stays put.
    @State private var followsEnd = true
    /// The person is scrolling, as opposed to the log growing under a still view.
    @State private var isScrolling = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xs) {
                    if controller.shownLog.isEmpty {
                        Text("What each run did shows here, step by step: who passed what to whom, which way each decision went, and why a run stopped.")
                            .textRole(.body)
                            .foregroundStyle(Theme.inkSecondary.ui)
                    }
                    ForEach(controller.shownLog) { line in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Text(RunClock.time(line.date, seconds: true))
                                .foregroundStyle(Theme.inkSecondary.ui)
                            Text(line.text)
                                .foregroundStyle(Theme.ink.ui)
                                .textSelection(.enabled)
                        }
                        .id(line.id)
                    }
                }
                .textRole(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.m)
            }
            .onScrollPhaseChange { _, phase in isScrolling = phase == .interacting || phase == .decelerating || phase == .tracking }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, atEnd in
                // New lines make the log longer without anyone scrolling; only the person scrolling away stops it following.
                if atEnd || isScrolling { followsEnd = atEnd }
            }
            // By the last line, not the count: a full log stays the same length as it turns over.
            .onChange(of: controller.shownLog.last?.id) {
                if followsEnd, let last = controller.shownLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            // Another run's log starts at its end.
            .onChange(of: controller.viewedRunID) {
                followsEnd = true
                if let last = controller.shownLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onAppear {
                if let last = controller.shownLog.last { proxy.scrollTo(last.id, anchor: .bottom) }
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
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if ends.isEmpty {
                    Text("Add an End card to collect a run's final answer here.")
                        .textRole(.body)
                        .foregroundStyle(Theme.inkSecondary.ui)
                }
                ForEach(ends) { card in
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
                            Text(card.name).textRole(.label)
                            Spacer()
                            if let file = card.saveTo, !file.isEmpty, controller.results[card.id] != nil {
                                Button(file) {
                                    NSWorkspace.shared.activateFileViewerSelecting([controller.project.root.appendingPathComponent(file)])
                                }
                                .buttonStyle(.link)
                                .textRole(.caption)
                                .help("Show the saved file in Finder")
                            }
                        }
                        if let text = controller.results[card.id] {
                            Text(text)
                                .textRole(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Space.m)
                                .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: DS.Radius.m))
                        } else {
                            Text("Nothing yet. This fills in when a run reaches the card.")
                                .textRole(.body)
                                .foregroundStyle(Theme.inkSecondary.ui)
                        }
                    }
                    .foregroundStyle(Theme.ink.ui)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.m)
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
