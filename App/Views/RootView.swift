import QueenBeeCore
import SwiftUI

/// The tabs of the panel beside the canvas.
enum PanelTab: String, CaseIterable {
    case orchestrator, log, output

    var label: String {
        switch self {
        case .orchestrator: "Orchestrator"
        case .log: "Log"
        case .output: "Output"
        }
    }
}

/// The app's one window: projects and their flows on the left, the selected flow's canvas
/// in the middle, and a panel for its orchestrator, log and output on the right.
struct WorkspaceView: View {
    @State private var showsPanel = true
    @State private var tab = PanelTab.orchestrator
    private var services: AppServices { AppServices.shared }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 340)
        } detail: {
            if let controller = services.current {
                FlowView(controller: controller, showsPanel: $showsPanel, tab: $tab)
                    .id(controller.flow.id)
            } else if services.projects.isEmpty {
                WelcomeView()
            } else {
                ContentUnavailableView("No flow selected", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Pick a flow in the sidebar, or add one to a project."))
            }
        }
        .navigationTitle(services.current?.flow.name ?? "Queen Bee")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
    }

    private var subtitle: String {
        guard let controller = services.current else { return "" }
        let project = controller.project.name
        if controller.isRunning { return "\(project) · running, \(controller.handOffs) hand-offs" }
        return project
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let controller = services.current {
                let waiting = controller.cardsNeedingYou
                if let first = waiting.first {
                    Button {
                        controller.select(.card(first.id))
                        controller.canvas?.zoom(toCard: first.id)
                    } label: {
                        Label(waiting.count == 1 ? "1 needs you" : "\(waiting.count) need you", systemImage: "hand.raised")
                            .labelStyle(.titleAndIcon)
                    }
                    .tint(Theme.live.ui)
                    .help("Go to the card that is waiting on you")
                }
                if controller.isRunning {
                    Button { Task { await controller.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                        .help("Stop the run")
                } else {
                    Button { Task { await controller.run() } } label: { Label("Run", systemImage: "play.fill") }
                        .help("Run the flow from its Start card")
                }
                Button { showsPanel.toggle() } label: { Label("Panel", systemImage: "sidebar.trailing") }
                    .help("Show or hide the orchestrator, log and output")
            }
        }
    }

    static func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        panel.message = "Flows are kept in a .queenbee folder inside the project, and agents work in the project folder."
        if panel.runModal() == .OK, let url = panel.url {
            let project = AppServices.shared.addProject(url)
            if project.controllers.isEmpty { project.newFlow() }
        }
    }
}

/// One flow: its canvas with the controls that float on it, and the side panel.
struct FlowView: View {
    let controller: FlowController
    @Binding var showsPanel: Bool
    @Binding var tab: PanelTab
    @AppStorage("panelWidth") private var panelWidth = 420.0
    private var services: AppServices { AppServices.shared }

    var body: some View {
        HStack(spacing: 0) {
            canvas
                .frame(minWidth: 420, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
            if showsPanel {
                PanelDivider(width: $panelWidth)
                SidePanel(controller: controller, tab: $tab)
                    .frame(width: panelWidth)
            }
        }
    }

    private var canvas: some View {
        CanvasRepresentable(controller: controller)
            .overlay(alignment: .topLeading) {
                PaletteView(controller: controller).padding(Theme.Space.m)
            }
            .overlay(alignment: .topTrailing) {
                if controller.selection != .none {
                    InspectorView(controller: controller).padding(Theme.Space.m)
                }
            }
            .overlay(alignment: .top) {
                if let message = services.problem ?? controller.banner {
                    BannerView(text: message) { controller.banner = nil }.padding(.top, Theme.Space.m)
                }
            }
            .overlay(alignment: .bottomLeading) {
                StatusStrip(controller: controller) {
                    tab = .log
                    showsPanel = true
                }
                .padding(Theme.Space.m)
            }
            .overlay(alignment: .bottomTrailing) {
                ZoomPill(controller: controller).padding(Theme.Space.m)
            }
            .overlay {
                if controller.isBlank, !controller.promptDismissed {
                    BlankFlowPrompt(controller: controller) {
                        tab = .orchestrator
                        showsPanel = true
                    }
                }
            }
            .animation(.easeOut(duration: Theme.Motion.base), value: controller.selection)
    }
}

/// The line between the canvas and the side panel. Drag it to make the panel wider or narrower.
private struct PanelDivider: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Theme.ink.ui)
            .frame(width: 1)
            .overlay {
                // A wider strip than the line itself, so it is easy to catch.
                Color.clear
                    .frame(width: 9)
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
            }
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ink.ui)
            Text("Queen Bee")
                .font(.dsMono(22, .medium))
                .foregroundStyle(Theme.ink.ui)
            Text("Add a project folder to start. Its flows are kept in a .queenbee folder inside it, and agents work in that folder.")
                .font(.dsSans(Theme.Size.title))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary.ui)
                .frame(maxWidth: 420)
            Button("Add Project Folder…") { WorkspaceView.pickProjectFolder() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ui)
    }
}
