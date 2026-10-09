import SwiftUI

/// Project folders and their flows. Each flow's row says what it needs from you.
struct SidebarView: View {
    @State private var search = ""
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var deleting: FlowController?
    private var services: AppServices { AppServices.shared }

    var body: some View {
        @Bindable var services = AppServices.shared
        List(selection: $services.selectedFlowID) {
            let pinned = services.allFlows.filter { services.pinnedFlowIDs.contains($0.flow.id) && matches($0) }
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned, id: \.flow.id) { row(for: $0).tag($0.flow.id) }
                }
            }
            ForEach(services.projects, id: \.root) { project in
                Section {
                    ForEach(project.controllers.filter(matches), id: \.flow.id) { controller in
                        row(for: controller).tag(controller.flow.id)
                    }
                    ForEach(project.unreadable, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .help("This file isn't a flow Queen Bee can read. It is left untouched.")
                    }
                } header: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        Button { project.newFlow() } label: { Image(systemName: "plus") }
                            .buttonStyle(.borderless)
                            .help("New flow in \(project.name)")
                    }
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.root]) }
                        Button("Remove from Sidebar") { services.removeProject(project) }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Flows and cards")
        .safeAreaInset(edge: .bottom) {
            Button { WorkspaceView.pickProjectFolder() } label: { Label("Add Project Folder…", systemImage: "folder.badge.plus") }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .confirmationDialog("Delete \"\(deleting?.flow.name ?? "")\"?",
                            isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Flow", role: .destructive) {
                if let deleting { deleting.project.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("Its sessions are stopped and its file is removed. The agents' chats stay in Claude Code's history.")
        }
    }

    /// A flow matches a search by its own name or by the name of any card in it.
    private func matches(_ controller: FlowController) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return controller.flow.name.localizedCaseInsensitiveContains(query)
            || controller.flow.cards.contains { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private func row(for controller: FlowController) -> some View {
        let id = controller.flow.id
        Group {
            if renaming == id {
                TextField("Name", text: $draftName)
                    .onSubmit {
                        controller.rename(to: draftName)
                        renaming = nil
                    }
            } else {
                HStack(spacing: 6) {
                    Label(controller.flow.name, systemImage: "point.3.connected.trianglepath.dotted")
                    Spacer(minLength: 4)
                    activity(of: controller)
                }
            }
        }
        .contextMenu {
            Button("Rename") { draftName = controller.flow.name; renaming = id }
            Button(services.pinnedFlowIDs.contains(id) ? "Unpin" : "Pin") { services.togglePin(id) }
            Button("Stop Its Sessions") { controller.shutDown() }
            Divider()
            Button("Delete…", role: .destructive) { deleting = controller }
        }
    }

    @ViewBuilder
    private func activity(of controller: FlowController) -> some View {
        switch controller.activity {
        case .needsYou: Badge(text: "needs you", tone: .live)
        case .running: Badge(text: "running", tone: .live)
        case .failed: Badge(text: "stopped", tone: .fail)
        case .quiet: EmptyView()
        }
    }
}
