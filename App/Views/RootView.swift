import QueenBeeCore
import QueenBeeDesign
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

/// The app's one window, flat from edge to edge: the sidebar sits on the window's own colour, a hairline away
/// from the flow, which has its header and tabs along the top and the side panel down its right.
struct WorkspaceView: View {
    static let gap = DS.Space.m

    @AppStorage("showsSidebar") private var showsSidebar = true
    @AppStorage("showsPanel") private var showsPanel = true
    @AppStorage("panelWidth") private var panelWidth = 420.0
    @State private var tab = PanelTab.orchestrator
    @Environment(\.openWindow) private var openWindow
    private var services: AppServices { AppServices.shared }

    var body: some View {
        ZStack {
            Palette.chrome.color.ignoresSafeArea()
            HStack(spacing: 0) {
                if showsSidebar {
                    SidebarView()
                        .frame(width: DS.Size.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    DSDivider(vertical: true)
                }
                Group {
                    if services.place == .flow { panel } else { PlaceView(place: services.place, showsSidebar: $showsSidebar) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.panel.color)
            }
            .ignoresSafeArea()

            if services.showsFind {
                // Over everything, near the top, like a search field that came to you.
                VStack {
                    FindPanel { services.showsFind = false }
                        .padding(.top, DS.Size.findInset)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Palette.scrim.color.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { services.showsFind = false }
                }
                .transition(.opacity.combined(with: .offset(y: -8)))
            }

            if services.showsPalette, let controller = services.current {
                VStack {
                    CommandPalette(controller: controller) { services.showsPalette = false }
                        .padding(.top, DS.Size.commandInset)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Palette.scrim.color.ignoresSafeArea().contentShape(Rectangle()).onTapGesture { services.showsPalette = false }
                }
                .transition(.opacity.combined(with: .offset(y: -8)))
            }

            if services.showsWelcome {
                OnboardingView { services.closeWelcome() }
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.standard, value: services.showsWelcome)
        .animation(Theme.Motion.standard, value: services.showsFind)
        .animation(Theme.Motion.standard, value: services.showsPalette)
        // The menu bar item normally gives the way to open the window again; this is for when it hasn't appeared.
        .onAppear { if services.openWorkspace == nil { services.openWorkspace = { openWindow(id: AppServices.workspaceID) } } }
        .animation(Theme.Motion.standard, value: showsSidebar)
        .animation(Theme.Motion.standard, value: showsPanel)
        .onChange(of: obstruction, initial: true) { services.canvasObstruction = obstruction }
        .navigationTitle(services.current?.flow.name ?? "Queen Bee")
        // The first time a flow opens in a git repository, it asks where it works. Its agents wait for the answer.
        .sheet(isPresented: Binding(get: { services.current?.asksForWorkplace == true }, set: { shown in
            guard !shown, let controller = services.current, controller.asksForWorkplace else { return }
            Task { await controller.answerWorkplaceQuestion(nil) }
        })) {
            if let controller = services.current {
                WorkplaceForm(controller: controller, isFirstRun: true) {}
                    .presentationBackground(Theme.surface.ui)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    /// The flow: the header, and the flow with the side panel beside it.
    private var panel: some View {
        VStack(spacing: 0) {
            FlowHeader(controller: services.current, showsSidebar: $showsSidebar, showsPanel: $showsPanel)
            DSDivider()
            HStack(spacing: 0) {
                ZStack {
                    if let controller = services.current {
                        CanvasRepresentable(controller: controller)
                            .id(controller.objectID)
                        CanvasControls(controller: controller) {
                            tab = .log
                            showsPanel = true
                        } showOrchestrator: {
                            tab = .orchestrator
                            showsPanel = true
                        }
                        .environment(\.orchestratorIsShowing, showsPanel && tab == .orchestrator)
                        .padding(Self.gap)
                        .id(controller.objectID)
                        FlowSettingsButton(controller: controller)
                            .padding(Self.gap)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .id(controller.objectID)
                    } else if services.projects.isEmpty {
                        WelcomeView()
                    } else {
                        ContentUnavailableView("No flow selected", systemImage: "point.3.connected.trianglepath.dotted",
                                               description: Text("Pick a flow on the left, or add one to a project."))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                if showsPanel, let controller = services.current {
                    DSDivider(vertical: true)
                    SidePanel(controller: controller, tab: $tab, width: $panelWidth)
                        .frame(width: panelWidth)
                        .id(controller.objectID)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        // A sheet over the canvas, so the flow stays where it was behind it.
        .sheet(isPresented: Binding(get: { services.current?.showsFlowSettings == true },
                                    set: { if !$0 { services.current?.showsFlowSettings = false } })) {
            if let controller = services.current {
                FlowSettingsSheet(controller: controller)
                    // Another flow's settings are a new page, not this one's fields carried over.
                    .id(controller.objectID)
                    .presentationBackground(Palette.panel.color)
            }
        }
    }

    /// How much of the canvas's left and right the floating controls cover, so "fit" can keep the flow clear of them.
    private var obstruction: CanvasObstruction {
        CanvasObstruction(left: Self.gap + PaletteView.width + Self.gap, right: Self.gap)
    }

    static func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Add"
        panel.message = "Choose the folder your agents should work in. Your flows are saved inside it."
        if panel.runModal() == .OK, let url = panel.url, AppServices.shared.confirmTrust(url) {
            let project = AppServices.shared.addProject(url)
            if project.controllers.isEmpty { project.newFlow() }
        }
    }
}

/// What floats over the canvas between the two panels: the palette, the selected card's
/// settings, a banner, the status line, the zoom control, and an empty flow's pointer to the
/// orchestrator. Its empty
/// areas let clicks through to the canvas underneath.
struct CanvasControls: View {
    let controller: FlowController
    let showLog: () -> Void
    let showOrchestrator: () -> Void
    @Environment(\.orchestratorIsShowing) private var orchestratorIsShowing
    @AppStorage("showsMinimap") private var showsMinimap = true
    private var services: AppServices { AppServices.shared }

    /// An empty flow points at the orchestrator until it is built in, or the note is closed.
    private var showsCallout: Bool {
        controller.isBlank && controller.selection == .none && !services.dismissedHints.contains(controller.flow.id)
    }

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) { PaletteView(controller: controller) }
            .overlay(alignment: .topTrailing) {
                if controller.selection != .none {
                    // Under the settings button, which has this corner.
                    InspectorView(controller: controller)
                        .padding(.top, DS.Size.bar + DS.Space.s)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                }
            }
            .overlay(alignment: .top) {
                if let message = services.problem ?? controller.banner {
                    BannerView(text: message) {
                        if services.problem != nil { services.dismissProblem() } else { controller.banner = nil }
                    }
                }
            }
            .overlay(alignment: .bottomLeading) { StatusStrip(controller: controller, showLog: showLog) }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: DS.Space.s) {
                    if showsMinimap, !controller.flow.cards.isEmpty, !controller.showsCost {
                        Minimap(controller: controller)
                            .transition(.opacity)
                    }
                    if controller.showsCost {
                        CostBreakdown(controller: controller) { controller.showsCost = false }
                            .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                    HStack(spacing: DS.Space.s) {
                        CostPill(controller: controller, showsBreakdown: Binding(get: { controller.showsCost }, set: { controller.showsCost = $0 }))
                        ZoomPill(controller: controller)
                    }
                }
                .animation(Theme.Motion.standard, value: controller.showsCost)
            }
            .overlay(alignment: .trailing) {
                if showsCallout {
                    // Below the middle of the panel's edge: clear of a new flow's cards, which sit at
                    // the top or, in a sub-flow shown whole, across the middle, and of the map at the foot.
                    OrchestratorCallout(controller: controller, orchestratorIsShowing: orchestratorIsShowing, showOrchestrator: showOrchestrator)
                        .padding(.top, DS.Size.calloutInset)
                        .transition(.opacity.combined(with: .offset(x: -8)))
                }
            }
            .animation(Theme.Motion.standard, value: controller.selection)
            .animation(Theme.Motion.standard, value: showsCallout)
    }
}

extension EnvironmentValues {
    /// The side panel is open on the orchestrator's tab.
    @Entry var orchestratorIsShowing = false
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .dsIcon(DS.IconSize.display, .light)
                .foregroundStyle(Theme.ink.ui)
            Text("Queen Bee")
                .textRole(.largeTitle)
                .foregroundStyle(Theme.ink.ui)
            Text("To start, choose the folder your agents should work in. Queen Bee saves your flows inside it.")
                .textRole(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSecondary.ui)
                .frame(maxWidth: 420)
            Button("Add Project Folder…") { WorkspaceView.pickProjectFolder() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(DS.Space.page)
    }
}
