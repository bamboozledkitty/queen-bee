import Foundation

/// The flows kept at the top of the sidebar. A flow is pinned by its project folder and its id, because a flow
/// copied into another open project keeps its id and the copy must not be pinned with it.
///
/// What was saved before pins named a folder is a bare id. It still pins that id's flow in whichever project has it,
/// as it did, until the pin is toggled.
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

    /// Pins the flow, or unpins it if it is pinned. Unpinning an old bare pin would unpin every copy of the flow,
    /// so the copies in `otherProjects`, the other open folders that have a flow with this id, are pinned by folder
    /// to keep them as they were.
    public mutating func toggle(project: String, id: String, otherProjects: [String] = []) {
        guard contains(project: project, id: id) else {
            entries.insert(Self.key(project, id))
            return
        }
        entries.remove(Self.key(project, id))
        if entries.remove(id) != nil {
            for other in otherProjects where other != project { entries.insert(Self.key(other, id)) }
        }
    }
}
