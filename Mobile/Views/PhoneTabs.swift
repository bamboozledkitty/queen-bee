import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// The places at the root of the iPhone app. Needs you and Flows are in the floating bar at the foot of the screen; Runs
/// and Schedules, which are read now and then, are in the menu the bar opens into.
enum PhoneTab: Hashable {
    case needsYou, flows, runs, schedules

    init(_ place: DevicePlace) {
        switch place {
        case .needsYou: self = .needsYou
        case .runs: self = .runs
        case .schedules: self = .schedules
        }
    }

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .flows: "Flows"
        case .runs: "Runs"
        case .schedules: "Schedules"
        }
    }
}

/// The bar that floats at the foot of the iPhone's first screen: Needs you, Flows, and a button that opens it into
/// a menu with the Mac, Settings and the pinned flows. A bar of the app's own, so it can open out, as Linear's does.
struct PhoneTabBar: View {
    @Environment(RemoteClient.self) private var client
    @Binding var tab: PhoneTab
    @Binding var showsMenu: Bool

    var body: some View {
        let waiting = client.mirror.library?.projects.contains { $0.flows.contains { $0.activity == .needsYou } } ?? false
        HStack(spacing: DS.Space.xxs) {
            tabButton(.needsYou, "Needs you", symbol: "tray", marked: waiting)
            tabButton(.flows, "Flows", symbol: "square.stack.3d.up", marked: false)
            Button { withAnimation(Theme.Motion.standard) { showsMenu.toggle() } } label: {
                Image(systemName: showsMenu ? "xmark" : "chevron.up.chevron.down")
                    .dsIcon(DS.IconSize.row, .semibold)
                    .foregroundStyle(Palette.textMuted.color)
                    .frame(width: DS.Size.tabMenuWidth, height: DS.Size.tabHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsMenu ? "Close the menu" : "More: your Mac, Settings and pinned flows")
        }
        .padding(DS.Space.tight)
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline.color))
    }

    private func tabButton(_ value: PhoneTab, _ title: String, symbol: String, marked: Bool) -> some View {
        let isOn = tab == value
        return Button {
            showsMenu = false
            tab = value
        } label: {
            Image(systemName: symbol)
                .dsIcon(DS.IconSize.tab)
                .foregroundStyle((isOn ? Palette.text : Palette.textMuted).color)
                .frame(width: DS.Size.tabWidth, height: DS.Size.tabHeight)
                .background((isOn ? Palette.selected : Palette.panel.opacity(0)).color, in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if marked { StatusDot(.live, size: DS.Size.dotTouch).padding(.top, DS.Space.snug).padding(.trailing, DS.Space.l) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// What the bar opens into: the Mac this device is paired with and how the connection is, Settings, and the
/// pinned flows, each a tap away.
struct PhoneMenu: View {
    @Environment(RemoteClient.self) private var client
    let showSettings: () -> Void
    /// Goes to a place the bar doesn't have a button for.
    let choose: (PhoneTab) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s) {
                ConnectionPill()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: DS.Size.touchTarget)
            DSDivider().padding(.horizontal, DS.Space.s)
            item("Runs", symbol: DevicePlace.runs.symbol) {
                close()
                choose(.runs)
            }
            item("Schedules", symbol: DevicePlace.schedules.symbol) {
                close()
                choose(.schedules)
            }
            item("Settings", symbol: "gearshape") {
                close()
                showSettings()
            }
            let pinned = client.pinnedFlows
            if !pinned.isEmpty {
                SectionHeader("Pinned").padding(.horizontal, DS.Space.s).padding(.top, DS.Space.xs)
                ForEach(Array(pinned.enumerated()), id: \.offset) { _, flow in
                    // A flow whose id another has too is not opened, and the row says why, as the list of flows does.
                    item(flow.name, note: flow.sharedID == true ? Remote.sharedFlowIDRefusal : nil, tone: flow.activity.tone) {
                        guard flow.sharedID != true else { return }
                        close()
                        client.open(flow.id)
                    }
                }
            }
        }
        .padding(.vertical, DS.Space.xs)
        .frame(width: DS.Size.menuNarrowWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous).strokeBorder(Palette.hairline.color))
    }

    private func item(_ title: String, note: String? = nil, symbol: String? = nil, tone: StatusTone? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                Group {
                    if let symbol { Image(systemName: symbol).dsIcon(DS.IconSize.bar) }
                    if let tone { StatusDot(tone, size: DS.Size.dotTouch) }
                }
                .foregroundStyle(Palette.textMuted.color)
                .frame(width: DS.Size.iconSlotRow)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).textRole(.label).foregroundStyle(Palette.text.color).lineLimit(1)
                    if let note {
                        Text(note).textRole(.caption).foregroundStyle(Palette.textMuted.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.l)
            .padding(.vertical, note == nil ? 0 : DS.Space.xs)
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension FlowActivity {
    /// The state as a colour: what the flow's dot shows.
    var tone: StatusTone {
        switch self {
        case .needsYou: .live
        case .running: .accent
        case .failed: .fail
        case .quiet: .neutral
        }
    }
}

/// Every flow that waits on you, across the Mac's projects, as the Mac's Needs you does. Tap one to open it.
/// A flow that is only running, or stopped, is in the list of flows with its state.
struct WaitingList: View {
    @Environment(RemoteClient.self) private var client

    private struct Entry: Identifiable {
        let project: RemoteProject
        let flow: RemoteFlowSummary
        var id: String { "\(project.id)/\(flow.id)" }
    }

    var body: some View {
        let all = (client.mirror.library?.projects ?? []).flatMap { project in project.flows.map { Entry(project: project, flow: $0) } }
        let waiting = all.filter { $0.flow.activity == .needsYou }
        Group {
            if waiting.isEmpty {
                VStack(spacing: DS.Space.m) {
                    Image(systemName: "checkmark.circle").dsIcon(DS.IconSize.empty, .light).foregroundStyle(Palette.textFaint.color)
                    Text("Nothing needs you").textRole(.headline).foregroundStyle(Palette.text.color)
                    Text("When a flow on your Mac waits for an answer, it shows here.")
                        .textRole(.body).foregroundStyle(Palette.textMuted.color).multilineTextAlignment(.center)
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        section("Waiting on you", waiting)
                    }
                    .padding(.bottom, DS.Size.floatingBarClearance)
                }
            }
        }
        .dimmedWhileAway(client.state == .connected)
        .background(Palette.panel.color)
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [Entry]) -> some View {
        if !entries.isEmpty {
            Text(title)
                .textRole(.sectionHeader)
                .foregroundStyle(Palette.textFaint.color)
                .padding(.horizontal, DS.Space.xl)
                .padding(.top, DS.Space.l)
                .padding(.bottom, DS.Space.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(entries) { entry in
                Button {
                    // One whose id another project's flow has too is not opened: the row says why.
                    if entry.flow.sharedID != true { client.open(entry.flow.id) }
                } label: {
                    HStack(spacing: DS.Space.m) {
                        StatusDot(entry.flow.activity.tone, size: DS.Size.dotTouch)
                            .frame(width: DS.Size.flowTile, height: DS.Size.flowTile)
                            .background(Palette.raised.color, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).strokeBorder(Palette.hairline.color))
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(entry.flow.name).textRole(.headline).foregroundStyle(Palette.text.color).lineLimit(1)
                            Text(entry.project.name).textRole(.caption).foregroundStyle(Palette.textMuted.color).lineLimit(1)
                            if entry.flow.sharedID == true {
                                Text(Remote.sharedFlowIDRefusal).textRole(.caption).foregroundStyle(Palette.textMuted.color)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: DS.Space.s)
                        FlowActivityBadge(activity: entry.flow.activity)
                    }
                    .padding(.horizontal, DS.Space.xl)
                    .padding(.vertical, DS.Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
