import QueenBeeDesign
import SwiftUI

/// The sidebar, on the window's own colour: what the app is, a search, and every project's flows. Each flow's
/// row says with its dot what it needs from you.
struct SidebarView: View {
    @State private var search = ""
    @State private var isSearching = false
    @FocusState private var searchFocused: Bool
    @State private var renaming: FlowController?
    @State private var draftName = ""
    @State private var deleting: FlowController?
    @Environment(\.openSettings) private var openSettings
    private var services: AppServices { AppServices.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's close, minimise and zoom buttons sit here.
            Color.clear.frame(height: DS.Size.bar)
            topRow
            if isSearching { searchField }
            places

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    let pinned = services.allFlows.filter { services.isPinned($0) && matches($0) }
                    if !pinned.isEmpty {
                        header("Pinned")
                        ForEach(pinned, id: \.objectID) { row(for: $0) }
                    }
                    ForEach(services.projects, id: \.root) { project in
                        header(project.name) {
                            Button { project.newFlow() } label: { Image(systemName: "plus").dsIcon(DS.IconSize.s, .semibold) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("New flow in \(project.name)")
                                .help("New flow in \(project.name)")
                        }
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.root]) }
                            Button("Remove from This List") { services.removeProject(project) }
                        }
                        ForEach(nested(project), id: \.controller.objectID) { entry in
                            row(for: entry.controller, outer: entry.outer)
                                .padding(.leading, CGFloat(entry.depth) * 14)
                        }
                        ForEach(project.unreadable, id: \.self) { url in
                            Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                                .textRole(.caption)
                                .foregroundStyle(Palette.failText.color)
                                .padding(.horizontal, DS.Space.s)
                                .padding(.vertical, DS.Space.xs)
                                .help("Queen Bee can't read this file as a flow, so it has left it alone.")
                        }
                    }
                }
                .padding(.horizontal, DS.Space.s)
                .padding(.bottom, DS.Space.s)
            }
            .scrollIndicators(.never)

            footer
        }
        .movesToTrash($deleting)
    }

    /// What is going on across every flow: what waits on you, the runs, the schedules, and the devices.
    private var places: some View {
        let waiting = services.needingYou.count
        let schedules = services.allFlows.reduce(0) { count, flow in count + flow.flow.cards.filter { $0.kind == .start && flow.isArmed($0) }.count }
        let devices = RemoteHost.shared.sessions.count
        return VStack(spacing: DS.Space.xxs) {
            place(.needsYou, "Needs you", icon: "tray") {
                if waiting > 0 { CountBadge(waiting, tone: .live) }
            }
            place(.runs, "Runs", icon: "play.circle") {
                if services.allFlows.contains(where: \.isRunning) { StatusDot(.live, size: 6) }
            }
            place(.schedules, "Schedules", icon: "clock") {
                if schedules > 0 { Text("\(schedules)").textRole(.caption).foregroundStyle(Palette.textMuted.color) }
            }
            place(.devices, "Devices", icon: "ipad.and.iphone") {
                if devices > 0 { StatusDot(.pass, size: 6) }
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.bottom, DS.Space.xs)
    }

    private func place<Trailing: View>(_ place: AppServices.Place, _ title: String, icon: String,
                                       @ViewBuilder trailing: () -> Trailing) -> some View {
        Button { services.place = place } label: {
            NavRow(title, selected: services.place == place) {
                Image(systemName: icon).dsIcon(DS.IconSize.l, .medium)
            } trailing: { trailing() }
        }
        .buttonStyle(.plain)
    }

    /// The app's menu, then search and a new flow.
    private var topRow: some View {
        HStack(spacing: DS.Space.xs) {
            Menu {
                Button("Add Project Folder…") { WorkspaceView.pickProjectFolder() }
                Button("Settings…") { openSettings() }
                Divider()
                Button("Welcome to Queen Bee") { services.showsWelcome = true }
            } label: {
                HStack(spacing: DS.Space.s) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Queen Bee").textRole(.headline).foregroundStyle(Palette.text.color)
                    Image(systemName: "chevron.down").dsIcon(DS.IconSize.xxs, .semibold).foregroundStyle(Palette.textFaint.color)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Queen Bee")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.ds(.ghost))
            .fixedSize()
            Spacer(minLength: 0)
            Button {
                isSearching.toggle()
                if isSearching { searchFocused = true } else { search = "" }
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.dsIcon)
                .accessibilityLabel("Search flows and cards")
                .help("Search flows and cards")
            Button { (services.current?.project ?? services.projects.first)?.newFlow() } label: { Image(systemName: "square.and.pencil") }
                .buttonStyle(.dsIcon)
                .disabled(services.projects.isEmpty)
                .accessibilityLabel("New flow")
                .help("New flow (⇧⌘N)")
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.bottom, DS.Space.s)
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.tight) {
            Image(systemName: "magnifyingglass").dsIcon(DS.IconSize.m, .medium).foregroundStyle(Palette.textFaint.color)
            TextField("Flows and cards", text: $search)
                .textFieldStyle(.plain)
                .textRole(.body)
                .focused($searchFocused)
                .onExitCommand { search = ""; isSearching = false }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textFaint.color)
                    .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: DS.Size.control)
        .raisedSurface(radius: DS.Radius.s)
        .padding(.horizontal, DS.Space.s)
        .padding(.bottom, DS.Space.s)
    }

    /// Who is connected from an iPad or iPhone, and adding a project.
    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            if !RemoteHost.shared.sessions.isEmpty {
                // "Can control" is read from the list of devices, which is watched, so turning it on or off shows here at once.
                let devices = RemoteHost.shared.devices
                let controls = RemoteHost.shared.sessions.contains { devices.canControl($0.device.id) }
                let names = RemoteHost.shared.sessions.map { devices.canControl($0.device.id) ? "\($0.device.name) · can control" : $0.device.name }
                    .joined(separator: ", ")
                HStack(spacing: DS.Space.s) {
                    Image(systemName: "ipad.and.iphone").frame(width: DS.Size.iconSlot)
                    Text(names).lineLimit(1)
                    Spacer(minLength: 0)
                    StatusDot(.pass, size: 6)
                }
                .textRole(.caption)
                .foregroundStyle(Palette.textMuted.color)
                .padding(.horizontal, DS.Space.s)
                .frame(height: DS.Size.navRow)
                .help(controls ? "Connected to this Mac now. A device that can control can start and stop runs, answer approvals, type into sessions and edit flows. You can turn that off, or remove a device, in Settings."
                      : "Connected to this Mac now. You can remove a device in Settings.")
            }
            Button { WorkspaceView.pickProjectFolder() } label: {
                NavRow("Add Project Folder…") { Image(systemName: "folder.badge.plus") }
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Space.s)
    }

    private func header(_ title: String) -> some View {
        header(title) { EmptyView() }
    }

    private func header<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        SectionHeader(title, trailing: trailing)
            .padding(.top, DS.Space.m)
            .contentShape(Rectangle())
    }

    /// A flow matches a search by its own name or by the name of any card in it.
    private func matches(_ controller: FlowController) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return controller.flow.name.localizedCaseInsensitiveContains(query)
            || controller.flow.cards.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// A project's flows in order, with each sub-flow listed under the flow whose Flow card
    /// runs it. A sub-flow nothing uses any more is listed with the rest, so it isn't lost.
    private func nested(_ project: ProjectModel) -> [(controller: FlowController, depth: Int, outer: FlowController?)] {
        let all = project.controllers
        func inner(of controller: FlowController) -> [FlowController] { controller.innerFlows }
        let used = Set(all.flatMap(inner).map(\.flow.id))
        var listed: Set<String> = []
        var rows: [(FlowController, Int, FlowController?)] = []
        func add(_ controller: FlowController, _ depth: Int, _ outer: FlowController?) {
            guard listed.insert(controller.flow.id).inserted else { return }
            if matches(controller) { rows.append((controller, depth, outer)) }
            for child in inner(of: controller) where child.flow.isSubflow == true { add(child, depth + 1, controller) }
        }
        for controller in all where !(controller.flow.isSubflow == true && used.contains(controller.flow.id)) { add(controller, 0, nil) }
        for controller in all { add(controller, 0, nil) }
        return rows
    }

    @ViewBuilder
    private func row(for controller: FlowController, outer: FlowController? = nil) -> some View {
        let id = controller.flow.id
        let selected = services.place == .flow && services.selectedFlow === controller
        Group {
            if renaming === controller {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .textRole(.body)
                    .onSubmit {
                        controller.rename(to: draftName)
                        renaming = nil
                    }
                    .onExitCommand { renaming = nil }
                    .padding(.horizontal, DS.Space.s)
                    .frame(height: DS.Size.navRow)
                    .raisedSurface(radius: DS.Radius.s)
            } else {
                Button {
                    // A sub-flow picked here is entered from the flow it sits under, so the way back shows.
                    if let outer {
                        services.enter(controller, from: outer)
                        controller.showWholeFlowSoon()
                    } else {
                        services.show(controller)
                    }
                } label: {
                    NavRow(controller.flow.name, selected: selected) {
                        if controller.flow.isSubflow == true {
                            Image(systemName: "arrow.turn.down.right").dsIcon(DS.IconSize.xs, .semibold)
                        } else {
                            // Needs you and Stopped say so in words beside the name, so they get no dot as well.
                            if controller.activity == .needsYou || controller.activity == .failed {
                                Color.clear
                            } else {
                                StatusDot(tone(of: controller))
                            }
                        }
                    } trailing: {
                        activity(of: controller)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(stateWords(of: controller) ?? "")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .contextMenu {
            Button("Rename") { draftName = controller.flow.name; renaming = controller }
            Button(services.isPinned(controller) ? "Unpin" : "Pin") { services.togglePin(controller) }
            Button("Stop Its Agents") { controller.shutDown() }
            Divider()
            Button("Move to Trash…", role: .destructive) { deleting = controller }
        }
    }

    private func tone(of controller: FlowController) -> StatusTone {
        switch controller.activity {
        case .needsYou: .live
        case .running: .accent
        case .failed: .fail
        case .quiet: .neutral
        }
    }

    /// What a screen reader says for the row's dot, which has no words of its own.
    private func stateWords(of controller: FlowController) -> String? {
        switch controller.activity {
        case .needsYou: "Needs you"
        case .running: "Running"
        case .failed: "Stopped"
        case .quiet: nil
        }
    }

    /// Words for the two states worth reading at a glance. Running shows by its dot alone, in the accent colour,
    /// which is not the orange of a flow that waits on you.
    @ViewBuilder
    private func activity(of controller: FlowController) -> some View {
        switch controller.activity {
        case .needsYou: Text("Needs you").textRole(.caption).foregroundStyle(Palette.liveText.color)
        case .failed: Text("Stopped").textRole(.caption).foregroundStyle(Palette.failText.color)
        case .running, .quiet: EmptyView()
        }
    }
}
