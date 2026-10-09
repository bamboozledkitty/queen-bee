import SwiftUI

/// The project's flows. Click one to put it on the canvas.
struct SidebarView: View {
    let project: ProjectModel
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var deleting: FlowController?

    var body: some View {
        @Bindable var project = project
        List(selection: $project.selectedFlowID) {
            Section("Flows") {
                ForEach(project.controllers, id: \.flow.id) { controller in
                    row(for: controller)
                        .tag(controller.flow.id)
                        .contextMenu {
                            Button("Rename") { draftName = controller.flow.name; renaming = controller.flow.id }
                            Button("Delete…", role: .destructive) { deleting = controller }
                        }
                }
            }
            if !project.unreadable.isEmpty {
                Section("Can't read") {
                    ForEach(project.unreadable, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .help("This file isn't a flow Queen Bee can read. It is left untouched.")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { project.newFlow() } label: { Label("New Flow", systemImage: "plus") }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .confirmationDialog("Delete \"\(deleting?.flow.name ?? "")\"?", isPresented: .init(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Flow", role: .destructive) {
                if let deleting { project.delete(deleting) }
                deleting = nil
            }
        } message: {
            Text("Its sessions are stopped and its file is removed. The agents' chats stay in Claude Code's history.")
        }
    }

    @ViewBuilder
    private func row(for controller: FlowController) -> some View {
        if renaming == controller.flow.id {
            TextField("Name", text: $draftName)
                .onSubmit {
                    controller.rename(to: draftName)
                    renaming = nil
                }
        } else {
            HStack {
                Label(controller.flow.name, systemImage: "point.3.connected.trianglepath.dotted")
                Spacer()
                if controller.isRunning {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }
}
