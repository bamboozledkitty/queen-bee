import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// One of the places above the projects in the sidebar, in the inset panel: what waits on you, the runs, the
/// schedules, or the paired devices, across every flow.
struct PlaceView: View {
    let place: AppServices.Place
    @Binding var showsSidebar: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.s) {
                if !showsSidebar { Spacer().frame(width: DS.Size.windowControlsInset) }
                Button { showsSidebar.toggle() } label: { Image(systemName: "sidebar.leading") }
                    .buttonStyle(.dsIcon)
                    .accessibilityLabel(showsSidebar ? "Hide projects" : "Show projects")
                Spacer()
            }
            .padding(.leading, DS.Space.s)
            .padding(.trailing, DS.Space.m)
            .frame(height: DS.Size.header)
            // The place's name is the page title, on the same left edge as its rows.
            HStack(spacing: DS.Space.s) {
                Image(systemName: icon).dsIcon(DS.IconSize.xl, .medium).foregroundStyle(Palette.textMuted.color)
                Text(title).textRole(.title).foregroundStyle(Palette.text.color)
                Spacer()
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.bottom, DS.Space.m)
            .frame(maxWidth: DS.Size.placeColumn)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            DSDivider()
            switch place {
            case .needsYou: NeedsYouList()
            case .runs: RunsList()
            case .schedules: SchedulesList()
            case .devices: DevicesPlace()
            case .flow: EmptyView()
            }
        }
    }

    private var title: String {
        switch place {
        case .needsYou: "Needs you"
        case .runs: "Runs"
        case .schedules: "Schedules"
        case .devices: "Devices"
        case .flow: ""
        }
    }

    private var icon: String {
        switch place {
        case .needsYou: "tray"
        case .runs: "play.circle"
        case .schedules: "clock"
        case .devices: "ipad.and.iphone"
        case .flow: "point.3.connected.trianglepath.dotted"
        }
    }
}

// MARK: Parts the places share

/// The label over a group of rows: a name and how many. Each row carries its own mark, so the label has none.
private struct GroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: DS.Space.s) {
            Text(title).textRole(.body).foregroundStyle(Palette.textMuted.color)
            Text("\(count)").textRole(.body).foregroundStyle(Palette.textFaint.color).monospacedDigit()
            Spacer()
        }
        .padding(.horizontal, DS.Space.xl)
        .frame(height: DS.Size.groupHeader)
        .overlay(alignment: .bottom) { DSDivider() }
        .accessibilityAddTraits(.isHeader)
    }
}

/// A row in a place's list: highlighted under the pointer, filled when chosen. The row itself is one button.
/// Controls of their own go in `trailing`, beside that button and not inside it, so each can be pressed alone.
private struct PlaceRow<Content: View, Trailing: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Button(action: action) {
                HStack(spacing: DS.Space.m) { content }
                    .textRole(.body)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.listRow, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            trailing
        }
        .padding(.horizontal, DS.Space.xl)
        .background((isSelected ? Palette.accentTint : isHovered ? Palette.hover : Palette.panel.opacity(0)).color)
        .overlay(alignment: .bottom) { DSDivider() }
        .onHover { isHovered = $0 }
    }
}

extension PlaceRow where Trailing == EmptyView {
    init(isSelected: Bool = false, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(isSelected: isSelected, action: action, content: content, trailing: { EmptyView() })
    }
}

/// A flow's name, as a small rounded tag at the end of a row.
private struct FlowTag: View {
    let controller: FlowController

    var body: some View {
        Text(controller.flow.name)
            .textRole(.caption)
            .foregroundStyle(Palette.textMuted.color)
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(height: DS.Size.tag)
            .overlay(Capsule().strokeBorder(Palette.hairlineStrong.color))
    }
}

/// What a place says when it has nothing to show.
private struct EmptyPlace: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: symbol).dsIcon(DS.IconSize.hero, .light).foregroundStyle(Palette.textFaint.color)
            Text(title).textRole(.headline).foregroundStyle(Palette.text.color)
            Text(text).textRole(.body).foregroundStyle(Palette.textMuted.color).multilineTextAlignment(.center).frame(maxWidth: DS.Size.emptyText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Needs you

/// Every card waiting on you, in every open project. Click one to go to it.
private struct NeedsYouList: View {
    private var services: AppServices { AppServices.shared }

    var body: some View {
        let waiting = services.needingYou
        if waiting.isEmpty {
            EmptyPlace(symbol: "checkmark.circle", title: "Nothing needs you",
                       text: "When an agent asks you something, or an Approval or Script card waits for your go-ahead, it shows here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    GroupHeader(title: "Waiting on you", count: waiting.count)
                    // A card's id is only unique in its flow, and a copied flow keeps its cards' ids.
                    ForEach(waiting.map { WaitingRow(controller: $0.controller, card: $0.card) }) { entry in
                        PlaceRow { services.reveal(entry.controller, cardID: entry.card.id) } content: {
                            Image(systemName: CanvasGeometry.icon(for: entry.card.kind))
                                .dsIcon(DS.IconSize.l, .medium)
                                .foregroundStyle(Palette.liveText.color)
                                .frame(width: DS.Size.iconSlot)
                            Text(entry.card.name).foregroundStyle(Palette.text.color).lineLimit(1)
                            Text(asks(entry.card, in: entry.controller)).foregroundStyle(Palette.textMuted.color).lineLimit(1)
                            Spacer(minLength: DS.Space.s)
                            FlowTag(controller: entry.controller)
                        } trailing: {
                            // The same go-to-the-card the row does when clicked, in a column of its own.
                            Button("Go to card") { services.reveal(entry.controller, cardID: entry.card.id) }
                                .buttonStyle(.ds(.ghost))
                        }
                    }
                }
                .frame(maxWidth: DS.Size.placeColumn)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func asks(_ card: Card, in controller: FlowController) -> String {
        switch card.kind {
        case .approval: "is waiting for your approval"
        case .script: "wants to run a command"
        default: "is asking you something in its terminal"
        }
    }
}

// MARK: Runs

/// Every flow's runs, the ones going now first, then the ones that stopped, then the ones that finished.
/// Choosing one shows its log beside the list.
struct RunsList: View {
    @State private var chosen: String?
    private var services: AppServices { AppServices.shared }

    private struct Entry: Identifiable {
        let controller: FlowController
        /// Nil for the run going now, which isn't recorded until it ends.
        let record: RunRecord?
        var id: String { "\(ObjectIdentifier(controller))/" + (record?.id ?? "live:\(controller.flow.id)") }
        var started: Date { record?.started ?? .distantFuture }
        var number: Int? { record.map(\.number) ?? controller.nextRunNumber }
    }

    var body: some View {
        let live = services.allFlows.filter(\.isRunning).map { Entry(controller: $0, record: nil) }
        let past = services.allFlows.flatMap { controller in controller.runs.map { Entry(controller: controller, record: $0) } }
            .sorted { $0.started > $1.started }
        let stopped = past.filter { $0.record?.outcome != .finished }
        let done = past.filter { $0.record?.outcome == .finished }
        if live.isEmpty && past.isEmpty {
            EmptyPlace(symbol: "play.circle", title: "No runs yet",
                       text: "Each time a flow runs, from its Run button, a schedule or the orchestrator, it is listed here with what it did and what it cost.")
        } else {
            let peeked = chosen.flatMap { id in (live + past).first { $0.id == id } }.flatMap { entry in entry.record.map { (entry, $0) } }
            GeometryReader { space in
                // The list keeps the page title's left edge when the peek opens, and gives up width on its right,
                // unless that would leave it under half its usual width.
                let listWidth = space.size.width - (peeked == nil ? 0 : DS.Size.placePeek + DS.Stroke.hairline)
                let inset = min(max(0, (space.size.width - DS.Size.placeColumn) / 2), max(0, listWidth - DS.Size.placeColumn / 2))
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            group("Running", live)
                            group("Stopped", stopped)
                            group("Done", done)
                        }
                        .frame(width: max(0, min(DS.Size.placeColumn, listWidth - inset)))
                        .padding(.leading, inset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: max(0, listWidth))
                    if let peeked {
                        DSDivider(vertical: true)
                        RunPeek(controller: peeked.0.controller, record: peeked.1) { chosen = nil }
                            .frame(width: DS.Size.placePeek)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [Entry]) -> some View {
        if !entries.isEmpty {
            GroupHeader(title: title, count: entries.count)
            ForEach(entries) { entry in
                PlaceRow(isSelected: chosen == entry.id) {
                    if entry.record == nil {
                        services.show(entry.controller)
                    } else {
                        chosen = chosen == entry.id ? nil : entry.id
                    }
                } content: {
                    Text(entry.number.map { "#\($0)" } ?? "")
                        .textRole(.monoCaption)
                        .foregroundStyle(Palette.textFaint.color)
                        .frame(width: DS.Size.runNumberColumn, alignment: .leading)
                    outcomeMark(entry.record)
                    Text(entry.controller.flow.name).foregroundStyle(Palette.text.color).lineLimit(1)
                    Text(detail(entry)).foregroundStyle(Palette.textMuted.color).lineLimit(1)
                    Spacer(minLength: DS.Space.s)
                    if let record = entry.record, !record.cost.isZero {
                        Text(record.cost.price).textRole(.monoCaption).foregroundStyle(Palette.textMuted.color)
                    }
                    Text(entry.record.map { RunPicker.label(for: $0.started) } ?? "now")
                        .textRole(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.textFaint.color)
                        .frame(width: DS.Size.runTimeColumn, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private func outcomeMark(_ record: RunRecord?) -> some View {
        Group {
            switch record?.outcome {
            case nil: StatusDot(.live, size: 7)
            case .finished?: Image(systemName: "checkmark").foregroundStyle(Palette.pass.color)
            case .stopped?: Image(systemName: "stop.fill").foregroundStyle(Palette.textMuted.color)
            case .failed?: Image(systemName: "xmark").foregroundStyle(Palette.fail.color)
            }
        }
        .dsIcon(DS.IconSize.m, .bold)
        .frame(width: DS.Size.iconSlot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.outcomeName(record))
    }

    private static func outcomeName(_ record: RunRecord?) -> String {
        switch record?.outcome {
        case nil: "Running"
        case .finished?: "Finished"
        case .stopped?: "Stopped"
        case .failed?: "Failed"
        }
    }

    private func detail(_ entry: Entry) -> String {
        guard let record = entry.record else { return "Running" + Self.handOffs(entry.controller.handOffs) }
        return record.summary + Self.handOffs(record.handOffs)
    }

    /// Only replies passed to agents count, so a run of scripts alone has none, and then nothing is said.
    static func handOffs(_ count: Int) -> String {
        count == 0 ? "" : " · \(count) \(count == 1 ? "hand-off" : "hand-offs")"
    }
}

/// One run beside the list: how it ended, its log, and the way to see it on the canvas.
private struct RunPeek: View {
    let controller: FlowController
    let record: RunRecord
    let close: () -> Void
    /// The run it is being compared with, while the comparison is open.
    @State private var comparedWith: RunRecord?
    private var services: AppServices { AppServices.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                HStack {
                    Text([record.number.map { "#\($0)" }, controller.project.name].compactMap { $0 }.joined(separator: " · "))
                        .textRole(.caption)
                        .foregroundStyle(Palette.textFaint.color)
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark") }
                        .buttonStyle(.dsIcon)
                        .accessibilityLabel("Close")
                }
                Text(controller.flow.name).textRole(.title).foregroundStyle(Palette.text.color)
                HStack(spacing: DS.Space.tight) {
                    StatusPill(record.summary, tone: record.outcome == .finished ? .pass : record.outcome == .failed ? .fail : .neutral)
                    if !record.cost.isZero { StatusPill(record.cost.price, tone: .neutral, dot: false) }
                }
            }
            .padding(DS.Space.l)
            DSDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(record.log) { line in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                            Text(RunClock.moment(line.date))
                                .textRole(.monoCaption)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textFaint.color)
                                .lineLimit(1)
                                .fixedSize()
                            Text(line.text).textRole(.body).foregroundStyle(Palette.textMuted.color)
                        }
                    }
                }
                .padding(DS.Space.l)
            }
            DSDivider()
            VStack(spacing: DS.Space.s) {
                compareMenu
                Button {
                    services.show(controller)
                    controller.view(run: record.id)
                } label: { Text("Show on the canvas").frame(maxWidth: .infinity) }
                    .buttonStyle(.ds(.secondary, wide: true))
            }
            .padding(DS.Space.m)
        }
        .sheet(item: $comparedWith) { other in
            if let comparison = RunComparison(record, other, in: controller.flow) {
                RunCompareSheet(flowName: controller.flow.name, comparison: comparison) { comparedWith = nil }
                    .presentationBackground(Palette.panel.color)
            }
        }
    }

    /// The flow's other kept runs, newest first, to set beside this one.
    @ViewBuilder
    private var compareMenu: some View {
        let others = controller.runs.reversed().filter { $0.id != record.id }
        Menu {
            ForEach(others) { other in
                Button("\(other.number.map { "Run \($0) · " } ?? "")\(RunPicker.label(for: other.started)) · \(other.summary)") { comparedWith = other }
            }
        } label: { Text("Compare with…").frame(maxWidth: .infinity) }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.ds(.secondary, wide: true))
            .disabled(others.isEmpty)
            .help(others.isEmpty ? "This flow has no other kept run to compare with" : "Set another run of this flow beside this one")
    }
}

// MARK: Schedules

/// Every Start card with a schedule, in every flow: which are on and when each runs next.
private struct SchedulesList: View {
    @State private var confirming: Entry?
    private var services: AppServices { AppServices.shared }

    private struct Entry: Identifiable {
        let controller: FlowController
        let card: Card
        let trigger: Trigger
        var id: String { "\(ObjectIdentifier(controller))/\(controller.flow.id)/\(card.id)" }
    }

    var body: some View {
        let all = services.allFlows.flatMap { controller in
            controller.flow.cards.compactMap { card in
                card.kind == .start ? card.trigger.map { Entry(controller: controller, card: card, trigger: $0) } : nil
            }
        }
        let on = all.filter { $0.controller.isArmed($0.card) }
        let off = all.filter { !$0.controller.isArmed($0.card) }
        if all.isEmpty {
            EmptyPlace(symbol: "clock", title: "No schedules",
                       text: "A Start card can run its flow on a schedule or when a file changes. Choose one in its settings, and it shows here.")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    group("On", on)
                    group("Off", off)
                }
                .frame(maxWidth: DS.Size.placeColumn)
                .frame(maxWidth: .infinity)
            }
            .confirmationDialog("Turn on this schedule?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible, presenting: confirming) { entry in
                Button("Turn on") {
                    // The person agreed to the command and the schedule they were shown. If either changed while the
                    // question was open, it is asked again with what the card says now, rather than turned on.
                    guard let now = entry.controller.flow.card(entry.card.id), let trigger = now.trigger else { return }
                    guard ScheduleShown.same(now, entry.card), trigger == entry.trigger else {
                        Task { @MainActor in confirming = Entry(controller: entry.controller, card: now, trigger: trigger) }
                        return
                    }
                    entry.controller.setTrigger(trigger, onCard: now.id)
                }
                Button("Cancel", role: .cancel) {}
            } message: { entry in
                Text(consequence(of: entry))
            }
        }
    }

    /// What turning the schedule on will do, in the words the person needs to agree to it.
    private func consequence(of entry: Entry) -> String {
        ScheduleShown.consequence(of: entry.card, trigger: entry.trigger, flow: entry.controller.flow.name)
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [Entry]) -> some View {
        if !entries.isEmpty {
            GroupHeader(title: title, count: entries.count)
            ForEach(entries) { entry in
                let armed = entry.controller.isArmed(entry.card)
                PlaceRow(action: { AppServices.shared.reveal(entry.controller, cardID: entry.card.id) }) {
                    Image(systemName: entry.trigger.kind == .file ? "doc" : "clock")
                        .dsIcon(DS.IconSize.l, .medium)
                        .foregroundStyle(Palette.textMuted.color)
                        .frame(width: DS.Size.iconSlot)
                    Text(entry.trigger.summary(in: .current)).foregroundStyle(Palette.text.color).lineLimit(1)
                    Text("from \(entry.card.name)").foregroundStyle(Palette.textMuted.color).lineLimit(1)
                    Spacer(minLength: DS.Space.s)
                    if armed, let next = entry.controller.nextFires[entry.card.id] {
                        Text("Next \(RunPicker.label(for: next))").textRole(.caption).monospacedDigit().foregroundStyle(Palette.textMuted.color)
                    }
                    FlowTag(controller: entry.controller)
                } trailing: {
                    if armed {
                        Button("Turn off") { entry.controller.turnScheduleOff(onCard: entry.card.id) }
                            .buttonStyle(.ds(.ghost))
                    } else {
                        // A schedule that came in the flow's file, or from an undo, runs only once it is turned on here,
                        // after being shown what it will run.
                        Button("Turn on") { confirming = entry }
                            .buttonStyle(.ds(.secondary))
                    }
                }
            }
        }
    }
}

// MARK: Devices

/// The paired iPads and iPhones, and pairing another: the same controls as in Settings.
private struct DevicesPlace: View {
    var body: some View {
        Form { RemoteSettingsSection() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: DS.Size.placeColumn)
            .frame(maxWidth: .infinity)
    }
}

/// A card waiting on the person, known by its flow as well as its own id.
private struct WaitingRow: Identifiable {
    let controller: FlowController
    let card: Card
    var id: String { "\(ObjectIdentifier(controller))/\(card.id)" }
}
