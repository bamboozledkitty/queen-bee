import QueenBeeCore
import SwiftUI

/// One window: a project folder once one is chosen, a welcome screen until then.
struct ProjectWindow: View {
    @Binding var folder: URL?

    var body: some View {
        Group {
            if let folder {
                RootView(project: AppServices.shared.project(for: folder))
                    .id(folder)
            } else {
                WelcomeView { folder = $0 }
            }
        }
        .onAppear {
            // `--open <folder>` on the command line opens that folder in the first window.
            if folder == nil, let path = LaunchArguments.takeFolder() { folder = URL(fileURLWithPath: path) }
        }
    }
}

enum LaunchArguments {
    private static var used = false

    /// `--float` keeps the window above others without taking focus. Terminals stop painting
    /// in a hidden window, so automated checks of the window need it on screen.
    static var floats: Bool { CommandLine.arguments.contains("--float") }

    static func takeFolder() -> String? {
        guard !used else { return nil }
        used = true
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct RootView: View {
    let project: ProjectModel
    @State private var showsOrchestrator = true
    @State private var showsLog = true
    private var services: AppServices { AppServices.shared }

    var body: some View {
        NavigationSplitView {
            SidebarView(project: project)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            if let controller = project.current {
                HSplitView {
                    VSplitView {
                        canvas(for: controller)
                            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
                            .layoutPriority(1)
                        if showsLog {
                            LogPanel(controller: controller)
                                .frame(minHeight: 70, idealHeight: 130, maxHeight: 260)
                        }
                    }
                    .layoutPriority(1)
                    if showsOrchestrator {
                        OrchestratorPane(controller: controller)
                            .frame(minWidth: 300, idealWidth: 400, maxWidth: 560)
                    }
                }
                .id(controller.flow.id)
            } else {
                ContentUnavailableView("No flow yet", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text("Create a flow to start placing agents on the canvas."))
            }
        }
        .navigationTitle(project.current?.flow.name ?? project.name)
        .navigationSubtitle(project.name)
        .toolbar { toolbar }
        .focusedSceneValue(\.project, project)
        .onDisappear { project.close() }
    }

    private func canvas(for controller: FlowController) -> some View {
        CanvasRepresentable(controller: controller)
            .overlay(alignment: .topTrailing) {
                if controller.selection != .none {
                    InspectorView(controller: controller)
                        .padding(12)
                }
            }
            .overlay(alignment: .top) {
                if let message = services.problem ?? controller.banner {
                    Text(message)
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.orange.opacity(0.6)))
                        .padding(.top, 10)
                        .onTapGesture { controller.banner = nil }
                }
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let controller = project.current {
                if controller.isRunning {
                    Button { Task { await controller.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                        .help("Stop the run")
                } else {
                    Button { Task { await controller.run() } } label: { Label("Run", systemImage: "play.fill") }
                        .help("Run the flow from its Start card")
                }
                Menu {
                    ForEach(CardKindMenu.kinds, id: \.self) { kind in
                        Button { controller.addCard(kind) } label: {
                            Label(kind.label, systemImage: CanvasGeometry.icon(for: kind))
                        }
                    }
                } label: {
                    Label("Add Card", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Add a card to the canvas")
                ControlGroup {
                    Button { controller.canvas?.zoom(by: 0.8) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                    Button { controller.canvas?.zoomToFit() } label: { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                    Button { controller.canvas?.zoom(by: 1.25) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                }
                Button { showsLog.toggle() } label: { Label("Log", systemImage: "list.bullet.rectangle") }
                    .help("Show or hide the run log")
                Button { showsOrchestrator.toggle() } label: { Label("Orchestrator", systemImage: "sidebar.trailing") }
                    .help("Show or hide the orchestrator")
            }
        }
    }
}

struct WelcomeView: View {
    let onPick: (URL) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Queen Bee")
                .font(.largeTitle.weight(.semibold))
            Text("Open a project folder. Its flows are kept in a .queenbee folder inside it, and agents work in that folder.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            Button("Open Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.prompt = "Open"
                if panel.runModal() == .OK, let url = panel.url { onPick(url) }
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(minWidth: 620, minHeight: 420)
    }
}
