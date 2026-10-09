import Foundation
import Observation
import QueenBeeCore

/// One open project folder: its flows, and which one is on the canvas.
@Observable
final class ProjectModel {
    let root: URL
    @ObservationIgnored let store: FlowStore
    private(set) var controllers: [FlowController] = []
    /// Flow files that couldn't be read. Listed, never written.
    private(set) var unreadable: [URL] = []
    var selectedFlowID: String? {
        didSet { current?.open() }
    }

    var current: FlowController? { controllers.first { $0.flow.id == selectedFlowID } }
    var name: String { root.lastPathComponent }

    init(root: URL) {
        self.root = root
        store = FlowStore(root: root)
        let loaded = store.loadAll()
        unreadable = loaded.unreadable
        controllers = loaded.flows.map { FlowController(flow: $0.flow, fileURL: $0.url, project: self) }
        controllers.forEach { AppServices.shared.register($0) }
        selectedFlowID = controllers.first?.flow.id
        current?.open()
    }

    @discardableResult
    func newFlow() -> FlowController? {
        var n = controllers.count + 1
        var name = "Flow \(n)"
        while controllers.contains(where: { $0.flow.name == name }) { n += 1; name = "Flow \(n)" }
        var flow = Flow(name: name)
        _ = try? flow.addCard(kind: .start, x: 80, y: 80)
        guard let url = try? store.save(flow, to: nil) else { return nil }
        let controller = FlowController(flow: flow, fileURL: url, project: self)
        controllers.append(controller)
        AppServices.shared.register(controller)
        selectedFlowID = flow.id
        return controller
    }

    func delete(_ controller: FlowController) {
        controller.shutDown()
        try? store.delete(controller.fileURL)
        AppServices.shared.unregister(flowID: controller.flow.id)
        controllers.removeAll { $0 === controller }
        if selectedFlowID == controller.flow.id { selectedFlowID = controllers.first?.flow.id }
    }

    /// The window closed: stop every session this project started.
    func close() {
        controllers.forEach { $0.shutDown(); AppServices.shared.unregister(flowID: $0.flow.id) }
        AppServices.shared.close(self)
    }
}
