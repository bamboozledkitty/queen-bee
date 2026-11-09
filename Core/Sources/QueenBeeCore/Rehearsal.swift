import Foundation

/// The rules of a rehearsal that need no window. A rehearsal runs the whole flow on Haiku at low effort, by
/// throwaway stand-ins of its agents, in a throwaway copy of where the flow works.
/// See docs/superpowers/specs/2026-11-09-rehearsal-mode-design.md.
public enum Rehearsal {
    public static let model = "haiku"
    public static let effort = "low"
    /// How many rehearsals a flow keeps, apart from its real runs.
    public static let keptLatest = 5

    public static let cantKeep = "A rehearsal can't be kept for good. Run the flow for real to keep a run."
}
