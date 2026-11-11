import Foundation

/// When Retry is offered. Retry gives a card the message it was given in the run that stopped there, all of it, and
/// starts a real run with it. Only the run that ended last keeps its messages whole: every other run keeps them cut
/// short (see `CarriedMessages`). So Retry is only for that run, and never while another is on show.
public enum Retry {
    /// Whether the canvas shows the run that ended last. Not while an earlier run is picked in the run picker
    /// (`viewed`), and not once Clear has put an older kept run on show in its place, which `runs.last` then is,
    /// below the highest number the flow has given.
    ///
    /// - Parameter viewed: the id of the earlier run picked, or nil for the latest.
    /// - Parameter highestNumber: the highest run number the flow has given, which clearing the log doesn't lower.
    public static func lastRunIsOnShow(viewed: String?, runs: [RunRecord], highestNumber: Int) -> Bool {
        guard viewed == nil else { return false }
        // Cleared with none kept: the canvas still holds the last run's marks and messages.
        guard let last = runs.last else { return true }
        // A run filed before runs were numbered is older than any numbered one, so it is the last to end only when
        // the flow has numbered none. Even then, one kept for good may be what Clear left of several unnumbered runs,
        // and nothing says whether it ended last, so Retry isn't offered on it. One that isn't kept is still listed,
        // so no Clear has passed it: it ended last.
        guard let number = last.number else { return highestNumber == 0 && !last.isKept }
        return number >= highestNumber
    }

    /// Why a paired device's Retry is refused while another run is on show.
    public static let notLastRun = "Retry is only for the run that ended last, and an older run is on show."
}
