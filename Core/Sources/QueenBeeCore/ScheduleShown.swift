import CryptoKit
import Foundation

/// What the person was shown of a Start card when they chose to turn its schedule on: the command it starts with
/// and when it runs. Only the Mac makes the fingerprint, and sends it with the flow in
/// `RemoteEditState.scheduleFingerprints`. A device sends back the one it showed with `RemoteCommand.armSchedule`,
/// and the Mac turns the schedule on only if the card says the same now, as the Mac's own "Turn on this schedule?"
/// does. As both ends of the check are the Mac's, a device that reads a card differently, being older or newer,
/// can't make them disagree.
public enum ScheduleShown {
    /// One fingerprint for the card's command and its schedule. A card with no command counts as one with an empty
    /// command, as the Mac shows it and arms it. Nil for a card with no schedule, which has nothing to turn on.
    public static func fingerprint(of card: Card) -> String? {
        guard let trigger = card.trigger else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(Shown(command: card.command ?? "", trigger: trigger)) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The fingerprint of every Start card with a schedule, by card id, for `RemoteEditState.scheduleFingerprints`.
    public static func fingerprints(of flow: Flow) -> [String: String] {
        var all: [String: String] = [:]
        for card in flow.cards where card.kind == .start { all[card.id] = fingerprint(of: card) }
        return all
    }

    /// Whether the card says what the person was shown. Nil for `shown` is a device that didn't say what it showed,
    /// which is taken as it always was: see `SECURITY.md`.
    public static func matches(_ shown: String?, _ card: Card) -> Bool {
        guard let shown else { return true }
        return fingerprint(of: card) == shown
    }

    /// Whether two copies of a card would be turned on for the same command and schedule.
    public static func same(_ one: Card, _ other: Card) -> Bool {
        (one.command ?? "") == (other.command ?? "") && one.trigger == other.trigger
    }

    /// What turning the schedule on will do, in the words the person needs to agree to it. `onDevice` is for the
    /// iPad and iPhone, whose Queen Bee isn't the one that runs it. `macChecks` false is a Mac that turns on
    /// whatever the card says when the command arrives, and the person is told so.
    public static func consequence(of card: Card, trigger: Trigger, flow: String, locale: Locale = .current,
                                   onDevice: Bool = false, macChecks: Bool = true) -> String {
        let command = (card.command ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = command.count > shownLimit ? String(command.prefix(shownLimit)) + "…" : command
        let begins = shown.isEmpty ? "with no command" : "with this command: \(shown)"
        var text = "\(trigger.summary(in: locale)), \(flow) runs from \(card.name) with nobody watching, starting \(begins)\n"
            + (onDevice ? "Queen Bee has to be open on your Mac for it to run." : "Queen Bee has to be open for it to run.")
        if onDevice, !macChecks {
            text += "\nYour Mac doesn't check whether this changes before it is turned on. Update Queen Bee on your Mac to have it checked."
        }
        return text
    }

    /// The most of a command the question shows.
    static let shownLimit = 300

    private struct Shown: Encodable {
        let command: String
        let trigger: Trigger
    }
}

/// A device's "Turn on this schedule?" for one Start card: what it showed, and when to ask again because the card
/// changed under it. The view only shows `open` and passes on what the person does.
public struct ScheduleQuestion: Equatable, Sendable {
    /// The card as the question showed it, with the fingerprint the Mac sent for it then, if any.
    public struct Shown: Equatable, Sendable {
        public var card: Card
        public var fingerprint: String?

        public init(card: Card, fingerprint: String?) { self.card = card; self.fingerprint = fingerprint }
    }

    /// What the question shows while it is open.
    public private(set) var open: Shown?
    /// Turn on was turned down, here or by the Mac, for a card that had changed since it was shown.
    private var asksAgain = false

    public init() {}

    /// Opens the question for the card as this device has it now. Nothing when it has no card with a schedule.
    public mutating func ask(_ card: Card?, fingerprint: String?) {
        open = card.flatMap { $0.trigger == nil ? nil : Shown(card: $0, fingerprint: fingerprint) }
    }

    /// The question went away, answered or not.
    public mutating func close() { open = nil }

    /// The person chose Turn on for what they were shown. True when it goes to the Mac. False when the card here
    /// already says something else, and the question is to be asked again with that.
    public mutating func turnOn(_ shown: Shown, now: Card?) -> Bool {
        guard let now, now.trigger != nil, !ScheduleShown.same(now, shown.card) else { return true }
        asksAgain = true
        return false
    }

    /// The Mac turned it down. The Mac sends what has changed in the flow before it answers a command, so the card
    /// here is already what the Mac has: if it, or its fingerprint, is not what was shown, the question is asked
    /// again. Turned down for any other reason, it is not, and the Mac's reason is shown as it is.
    public mutating func refused(_ shown: Shown, now: Card?, fingerprint: String?) {
        guard let now, now.trigger != nil else { return }
        if !ScheduleShown.same(now, shown.card) || (shown.fingerprint != nil && fingerprint != shown.fingerprint) { asksAgain = true }
    }

    /// Asks again, once the question before has closed, with the card as this device has it now. True when it did.
    public mutating func askAgain(now: Card?, fingerprint: String?) -> Bool {
        guard asksAgain, open == nil, let now, now.trigger != nil else { return false }
        asksAgain = false
        open = Shown(card: now, fingerprint: fingerprint)
        return true
    }
}
