import Foundation

/// The flows kept at the top of the sidebar. A flow is pinned by its id alone, as older versions saved pins, so the
/// pin lasts when its project folder is moved or renamed and an older Queen Bee still reads it. Only a flow whose
/// id is also open in another project (a copied flow keeps its id) is pinned by its folder and id, so the copy is
/// not pinned with it.
public struct PinSet: Equatable, Sendable {
    private var entries: Set<String>

    public init(saved: [String] = []) { entries = Set(saved) }

    /// What to save: one string per pin, sorted.
    public var saved: [String] { entries.sorted() }

    private static func key(_ project: String, _ id: String) -> String { "\(project)\t\(id)" }

    public func contains(project: String, id: String) -> Bool {
        entries.contains(Self.key(project, id)) || entries.contains(id)
    }

    /// Every id pinned in any project.
    public var ids: Set<String> {
        Set(entries.map { entry in entry.lastIndex(of: "\t").map { String(entry[entry.index(after: $0)...]) } ?? entry })
    }

    /// Pins the flow, or unpins it if it is pinned. `otherProjects` are the open folders that have a flow with this
    /// id, this one included or not. With none but this one, the pin is the bare id. Unpinning a bare pin would
    /// unpin every copy of the flow, so the copies are pinned by folder to keep them as they were.
    public mutating func toggle(project: String, id: String, otherProjects: [String] = []) {
        let others = otherProjects.filter { $0 != project }
        guard contains(project: project, id: id) else {
            entries.insert(others.isEmpty ? id : Self.key(project, id))
            return
        }
        entries.remove(Self.key(project, id))
        if entries.remove(id) != nil {
            for other in others { entries.insert(Self.key(other, id)) }
        }
    }
}
