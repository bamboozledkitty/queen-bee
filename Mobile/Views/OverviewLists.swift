import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// The places the Mac has above its projects, as a device has them: what waits on you, the runs, and the schedules,
/// across every project the Mac has open. On an iPad they are rows above the flows in the list; on an iPhone, Needs
/// you is a tab and the other two are in the bar's menu. They are all read-only: a tap goes to the flow, and
/// whatever changes is changed there, or on the Mac.
enum DevicePlace: Hashable {
    case needsYou, runs, schedules

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .runs: "Runs"
        case .schedules: "Schedules"
        }
    }

    /// The Mac's own marks for them.
    var symbol: String {
        switch self {
        case .needsYou: "tray"
        case .runs: "play.circle"
        case .schedules: "clock"
        }
    }
}

extension RemoteClient {
    /// The flows waiting on the person, across every project: what the Needs you place counts.
    var flowsNeedingYou: Int {
        (mirror.library?.projects ?? []).reduce(0) { $0 + $1.flows.filter { $0.activity == .needsYou }.count }
    }

    /// A tap on a run: its flow opens, and the run goes on show on the canvas if the flow still has it. A run going
    /// now, which isn't kept yet, just opens its flow. Said nothing of a flow the Mac won't open: the row says why.
    func openRun(_ entry: RemoteRunEntry) {
        guard entry.sharedID != true else { return }
        if let id = entry.runID { canvas.wantedRun = (entry.flowID, id) }
        let isOpen = mirror.openFlowID == entry.flowID && !mirror.openFlowWentAway
        if !isOpen { open(entry.flowID) }
    }

    /// A tap on a schedule: its flow opens, with its Start card in the middle of the canvas, as the Mac's does.
    func openSchedule(_ entry: RemoteScheduleEntry) {
        guard entry.sharedID != true else { return }
        canvas.wantedCard = (entry.flowID, entry.cardName)
        if mirror.openFlowID != entry.flowID || mirror.openFlowWentAway {
            open(entry.flowID)
        } else {
            showWantedCard()
        }
    }
}

// MARK: The rows above the flows, on an iPad

/// Needs you, Runs and Schedules, above the projects in the list of flows on an iPad, as the Mac's sidebar has them.
struct PlaceRows: View {
    @Environment(RemoteClient.self) private var client
    let choose: (DevicePlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            ForEach([DevicePlace.needsYou, .runs, .schedules], id: \.self) { place in
                let count = place == .needsYou ? client.flowsNeedingYou : 0
                Button { choose(place) } label: {
                    HStack(spacing: Theme.Space.s) {
                        Image(systemName: place.symbol)
                            .dsIcon(DS.IconSize.row)
                            .foregroundStyle(Theme.inkSecondary.ui)
                            .frame(width: DS.Size.iconSlot)
                            .accessibilityHidden(true)
                        Text(place.title).textRole(.body).foregroundStyle(Theme.ink.ui)
                        Spacer(minLength: Theme.Space.xs)
                        if count > 0 { Badge(text: "\(count)", tone: .live) }
                        Image(systemName: "chevron.right")
                            .dsIcon(DS.IconSize.m, .semibold)
                            .foregroundStyle(Theme.inkSecondary.ui)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, Theme.Space.s)
                    .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(place.title)
                .accessibilityValue(count > 0 ? "\(count) waiting" : "")
            }
        }
        .padding(.top, Theme.Space.s)
    }
}

/// One of the places, in the list's column on an iPad: a way back to the flows, and the place under it.
struct PlaceScreen: View {
    let place: DevicePlace
    let back: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: back) {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "chevron.left").dsIcon(DS.IconSize.xxl, .semibold).accessibilityHidden(true)
                    Text("Flows").textRole(.body)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.select.ui)
                .padding(.horizontal, Theme.Space.m)
                .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to flows")
            Hairline()
            PlaceContent(place: place)
        }
        .background(Theme.surface.ui)
    }
}

/// The place itself.
struct PlaceContent: View {
    let place: DevicePlace

    var body: some View {
        switch place {
        case .needsYou: WaitingList()
        case .runs: RunsPlace()
        case .schedules: SchedulesPlace()
        }
    }
}

// MARK: Shared parts

/// What a place says when it has nothing to show, or the Mac can't show it yet.
private struct EmptyPlace: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: symbol).dsIcon(DS.IconSize.empty, .light).foregroundStyle(Theme.inkSecondary.ui).accessibilityHidden(true)
            Text(title).textRole(.heading).foregroundStyle(Theme.ink.ui)
            Text(text).textRole(.body).foregroundStyle(Theme.inkSecondary.ui).multilineTextAlignment(.center)
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The band over a group of rows: a mark, a name and how many.
private struct GroupHeader: View {
    let title: String
    let count: Int
    let tone: StatusTone

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            StatusDot(tone, size: DS.Size.dotTouch)
            Text(title).textRole(.label).foregroundStyle(Theme.ink.ui)
            Text("\(count)").textRole(.body).foregroundStyle(Theme.inkSecondary.ui).monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
        .background(Theme.bar.ui)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a place shows in place of its list while the Mac hasn't sent it: an older Mac says so, a newer one is on its way.
private struct NotYet: View {
    let symbol: String
    @Environment(RemoteClient.self) private var client

    var body: some View {
        if client.mirror.welcome != nil, !client.mirror.macHasOverview {
            EmptyPlace(symbol: symbol, title: "Not on your Mac yet", text: RemoteOverview.macIsOlder)
        } else {
            EmptyPlace(symbol: symbol, title: "Getting them…", text: "")
        }
    }
}

// MARK: Runs

/// Every flow's runs in every project the Mac has open: the ones going now, then the ones that stopped, then the
/// ones that finished, as the Mac's Runs place has them. A tap opens the run's flow with that run on show.
struct RunsPlace: View {
    @Environment(RemoteClient.self) private var client

    /// More than one project is open on the Mac.
    private var showsProject: Bool { (client.mirror.library?.projects.count ?? 0) > 1 }

    var body: some View {
        Group {
            if let overview = client.mirror.overview {
                let groups = overview.runGroups
                if groups.isEmpty {
                    EmptyPlace(symbol: DevicePlace.runs.symbol, title: "No runs yet",
                               text: "Each time a flow runs, from its Run button, a schedule or the orchestrator, it is listed here.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            group("Running", groups.running, tone: .live)
                            group("Stopped", groups.stopped, tone: .fail)
                            group("Done", groups.done, tone: .pass)
                        }
                        .padding(.bottom, DS.Size.floatingBarClearance)
                    }
                }
            } else {
                NotYet(symbol: DevicePlace.runs.symbol)
            }
        }
        .dimmedWhileAway(client.state == .connected)
        .background(Theme.surface.ui)
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [RemoteRunEntry], tone: StatusTone) -> some View {
        if !entries.isEmpty {
            GroupHeader(title: title, count: entries.count, tone: tone)
            ForEach(entries) { entry in OverviewRunRow(entry: entry, showsProject: showsProject) }
        }
    }
}

private struct OverviewRunRow: View {
    @Environment(RemoteClient.self) private var client
    let entry: RemoteRunEntry
    /// More than one project is open on the Mac, so the project says which flow this is.
    let showsProject: Bool

    var body: some View {
        Button { client.openRun(entry) } label: {
            HStack(spacing: Theme.Space.m) {
                mark.frame(width: DS.Size.iconSlotLarge)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: Theme.Space.s) {
                        Text(entry.flowName).textRole(.label).foregroundStyle(Theme.ink.ui).lineLimit(1)
                        if let number = entry.number {
                            Text("#\(number)").textRole(.monoCaption).foregroundStyle(Theme.inkSecondary.ui)
                        }
                    }
                    if showsProject {
                        Text(entry.projectName).textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui).lineLimit(1)
                    }
                    Text(detail).textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui).lineLimit(2)
                    if entry.sharedID == true {
                        Text(Remote.sharedFlowIDRefusal).textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.flowName)\(showsProject ? ", in \(entry.projectName)" : "")\(entry.number.map { ", run \($0)" } ?? ""), \(outcomeName)")
        .accessibilityValue(detail)
        .accessibilityHint(entry.sharedID == true ? "" : entry.runID == nil ? "Opens the flow." : "Opens the flow with this run on show.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var mark: some View {
        Group {
            switch entry.outcome {
            case nil: StatusDot(.live, size: DS.Size.dotTouch)
            case .finished?: Image(systemName: "checkmark").foregroundStyle(Theme.passInk.ui)
            case .stopped?: Image(systemName: "stop.fill").foregroundStyle(Theme.inkSecondary.ui)
            case .failed?: Image(systemName: "xmark").foregroundStyle(Theme.failInk.ui)
            }
        }
        .dsIcon(DS.IconSize.xl, .bold)
        .accessibilityHidden(true)
    }

    private var outcomeName: String {
        switch entry.outcome {
        case nil: "running"
        case .finished?: "finished"
        case .stopped?: "stopped"
        case .failed?: "failed"
        }
    }

    /// How it ended, its hand-offs and its cost, as the Mac's row has them.
    private var detail: String {
        // The time leads: a narrow list has no column for it beside the name.
        var text = "\(entry.started.map(Clock.run) ?? "Now") · \(entry.summary)"
        if entry.handOffs > 0 { text += " · \(entry.handOffs) \(entry.handOffs == 1 ? "hand-off" : "hand-offs")" }
        if let cost = entry.cost, !cost.isZero { text += " · \(cost.price)" }
        return text
    }
}

// MARK: Schedules

/// Every Start card with a schedule, in every flow: the ones that are on, then the ones that are off, and when each
/// runs next. Only shown. A schedule starts runs with nobody watching, so it is turned on or off on the Mac.
struct SchedulesPlace: View {
    @Environment(RemoteClient.self) private var client

    /// More than one project is open on the Mac.
    private var showsProject: Bool { (client.mirror.library?.projects.count ?? 0) > 1 }

    var body: some View {
        Group {
            if let overview = client.mirror.overview {
                if overview.schedules.isEmpty {
                    EmptyPlace(symbol: DevicePlace.schedules.symbol, title: "No schedules",
                               text: "A Start card can run its flow on a schedule or when a file changes. Choose one in its settings on your Mac, and it shows here.")
                } else {
                    let groups = overview.scheduleGroups
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            group("On", groups.on, tone: .pass)
                            group("Off", groups.off, tone: .neutral)
                            Text(RemoteOverview.schedulesAreForTheMac)
                                .textRole(.footnote)
                                .foregroundStyle(Theme.inkSecondary.ui)
                                .padding(.horizontal, Theme.Space.xl)
                                .padding(.vertical, Theme.Space.l)
                        }
                        .padding(.bottom, DS.Size.floatingBarClearance)
                    }
                }
            } else {
                NotYet(symbol: DevicePlace.schedules.symbol)
            }
        }
        .dimmedWhileAway(client.state == .connected)
        .background(Theme.surface.ui)
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [RemoteScheduleEntry], tone: StatusTone) -> some View {
        if !entries.isEmpty {
            GroupHeader(title: title, count: entries.count, tone: tone)
            ForEach(entries) { entry in OverviewScheduleRow(entry: entry, showsProject: showsProject) }
        }
    }
}

private struct OverviewScheduleRow: View {
    @Environment(RemoteClient.self) private var client
    let entry: RemoteScheduleEntry
    let showsProject: Bool

    var body: some View {
        Button { client.openSchedule(entry) } label: {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: entry.isFile ? "doc" : "clock")
                    .dsIcon(DS.IconSize.row)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .frame(width: DS.Size.iconSlotLarge)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(entry.summary).textRole(.label).foregroundStyle(Theme.ink.ui).lineLimit(2)
                    Text("from \(entry.cardName) in \(entry.flowName)\(showsProject ? ", \(entry.projectName)" : "")").textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui).lineLimit(1)
                    if entry.armed, let next = entry.next {
                        Text("Next \(Clock.run(next))").textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui)
                    }
                    if entry.sharedID == true {
                        Text(Remote.sharedFlowIDRefusal).textRole(.footnote).foregroundStyle(Theme.inkSecondary.ui)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.xs)
            .frame(maxWidth: .infinity, minHeight: Theme.Touch.target, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.summary), from \(entry.cardName) in \(entry.flowName)\(showsProject ? ", \(entry.projectName)" : "")")
        .accessibilityValue([entry.armed ? "On" : "Off", entry.armed ? entry.next.map { "next \(Clock.run($0))" } : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(entry.sharedID == true ? "" : "Opens the flow at its Start card.")
        .accessibilityAddTraits(.isButton)
    }
}
