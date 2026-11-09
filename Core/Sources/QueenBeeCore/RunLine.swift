import Foundation

/// How a run's line of stops is drawn: which stretches of the line are green, and, when the line is longer than its
/// panel, how many stops are out of view each way and where an arrow pages to.
public enum RunLine {
    /// Whether the stretch of line from each stop to the next is green, one for each pair. A stretch is green when
    /// the run reached the stops at both ends of it, so it is all one colour, and a stop the run hasn't reached never
    /// sits on green, even with stops the run did reach beyond it.
    public static func green(_ stops: [RunProgress.Stop]) -> [Bool] {
        zip(stops, stops.dropFirst()).map { $0.isReached && $1.isReached }
    }

    /// How many stops are not wholly in view before and after the part of the line that is, for a line of stops
    /// that are each `column` wide.
    public struct OutOfView: Equatable, Sendable {
        public var before: Int
        public var after: Int

        public init(before: Int = 0, after: Int = 0) {
            self.before = before
            self.after = after
        }

        /// `offset` is how far the line is scrolled, `content` how wide all its stops are, `width` how wide the part
        /// in view is. Less than half a point out of view counts as in view.
        public init(offset: Double, content: Double, width: Double, column: Double) {
            guard column > 0, width > 0 else { self.init(); return }
            func cut(_ hidden: Double) -> Int { max(0, Int(((hidden - 0.5) / column).rounded(.up))) }
            self.init(before: cut(offset), after: cut(content - offset - width))
        }

        /// The stop an arrow scrolls to, of `count`: going on, the last stop wholly in view, to go to the start of
        /// the view; going back, the first stop wholly in view, to go to its end. Either way the view moves on by
        /// what was in it, less the one stop that stays in sight. Nil when there is nothing more that way.
        public func pageTarget(back: Bool, count: Int) -> Int? {
            if back {
                return before > 0 ? min(before, count - 1) : nil
            }
            return after > 0 ? max(0, count - after - 1) : nil
        }
    }
}
