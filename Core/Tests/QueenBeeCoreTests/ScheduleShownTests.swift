import Foundation
import Testing
@testable import QueenBeeCore

/// Turning a schedule on from a device for the command and schedule it showed, and asking again when they changed.
@Suite struct ScheduleShownTests {
    private static var scheduled: Card {
        var start = Card.make(kind: .start, id: "go", name: "Go", x: 0, y: 0)
        start.command = "echo hi"
        start.trigger = Trigger(kind: .daily, hour: 9, minute: 30)
        return start
    }

    private static func changed(_ change: (inout Card) -> Void) -> Card {
        var card = scheduled
        change(&card)
        return card
    }

    // MARK: The fingerprint

    @Test func whatWasShownMatchesTheCardAsItWas() throws {
        let card = Self.scheduled
        let shown = try #require(ScheduleShown.fingerprint(of: card))
        #expect(ScheduleShown.matches(shown, card))
        // Other settings, and where it sits, are not what the person agreed to.
        let moved = Self.changed { $0.name = "Elsewhere"; $0.x = 900 }
        #expect(ScheduleShown.matches(shown, moved))
    }

    @Test func aChangedCommandOrScheduleIsNotWhatWasShown() throws {
        let shown = try #require(ScheduleShown.fingerprint(of: Self.scheduled))
        let command = Self.changed { $0.command = "rm -rf build" }
        let time = Self.changed { $0.trigger?.hour = 10 }
        let kind = Self.changed { $0.trigger = Trigger(kind: .interval, minutes: 1) }
        #expect(!ScheduleShown.matches(shown, command))
        #expect(!ScheduleShown.matches(shown, time))
        #expect(!ScheduleShown.matches(shown, kind))
        let gone = Self.changed { $0.trigger = nil }
        #expect(ScheduleShown.fingerprint(of: gone) == nil)
        #expect(!ScheduleShown.matches(shown, gone))
    }

    @Test func noCommandIsAnEmptyOne() {
        let none = Self.changed { $0.command = nil }
        let empty = Self.changed { $0.command = "" }
        #expect(ScheduleShown.fingerprint(of: none) == ScheduleShown.fingerprint(of: empty))
        #expect(ScheduleShown.same(none, empty))
    }

    @Test func aDeviceThatSaysNothingIsTakenAsBefore() {
        // An older device sends no `shown`. The Mac turns the schedule on as it always did: see SECURITY.md.
        #expect(ScheduleShown.matches(nil, Self.scheduled))
    }

    @Test func eachStartCardWithAScheduleHasOne() {
        var agent = Card.make(kind: .agent, id: "a", name: "A", x: 0, y: 0)
        agent.trigger = nil
        let bare = Card.make(kind: .start, id: "bare", name: "Bare", x: 0, y: 0)
        let flow = Flow(name: "F", cards: [Self.scheduled, agent, bare])
        #expect(ScheduleShown.fingerprints(of: flow) == ["go": ScheduleShown.fingerprint(of: Self.scheduled)!])
    }

    // MARK: The words

    @Test func theQuestionSaysWhenWhereAndWhat() {
        let card = Self.scheduled
        let mac = ScheduleShown.consequence(of: card, trigger: card.trigger!, flow: "Daily", locale: Locale(identifier: "en_GB"))
        #expect(mac == "Every day at 09:30, Daily runs from Go with nobody watching, starting with this command: echo hi\nQueen Bee has to be open for it to run.")
        let device = ScheduleShown.consequence(of: card, trigger: card.trigger!, flow: "Daily", locale: Locale(identifier: "en_GB"), onDevice: true)
        #expect(device.hasSuffix("\nQueen Bee has to be open on your Mac for it to run."))
        let older = ScheduleShown.consequence(of: card, trigger: card.trigger!, flow: "Daily", onDevice: true, macChecks: false)
        #expect(older.hasSuffix("Update Queen Bee on your Mac to have it checked."))
    }

    @Test func aLongCommandIsCutAndNoneIsSaid() {
        let long = Self.changed { $0.command = String(repeating: "a", count: 400) }
        let text = ScheduleShown.consequence(of: long, trigger: long.trigger!, flow: "F")
        #expect(text.contains(String(repeating: "a", count: ScheduleShown.shownLimit) + "…"))
        #expect(!text.contains(String(repeating: "a", count: ScheduleShown.shownLimit + 1)))
        let none = Self.changed { $0.command = "  " }
        #expect(ScheduleShown.consequence(of: none, trigger: none.trigger!, flow: "F").contains("starting with no command"))
    }

    // MARK: Asking

    @Test func turnOnGoesToTheMacWhenNothingChanged() {
        var question = ScheduleQuestion()
        question.ask(Self.scheduled, fingerprint: "one")
        let shown = question.open!
        question.close()
        let goes = question.turnOn(shown, now: Self.scheduled)
        #expect(goes)
        let askedAgain = question.askAgain(now: Self.scheduled, fingerprint: "one")
        #expect(!askedAgain)
    }

    @Test func aCardWithNoScheduleIsNotAsked() {
        var question = ScheduleQuestion()
        question.ask(Self.changed { $0.trigger = nil }, fingerprint: nil)
        #expect(question.open == nil)
        question.ask(nil, fingerprint: nil)
        #expect(question.open == nil)
    }

    @Test func aCardChangedHereIsAskedAgainOnceTheQuestionCloses() {
        var question = ScheduleQuestion()
        question.ask(Self.scheduled, fingerprint: "one")
        let shown = question.open!
        let now = Self.changed { $0.command = "echo bye" }
        let goes = question.turnOn(shown, now: now)
        #expect(!goes)
        // Not while the one before is still closing.
        let askedWhileClosing = question.askAgain(now: now, fingerprint: "two")
        #expect(!askedWhileClosing)
        question.close()
        let askedAgain = question.askAgain(now: now, fingerprint: "two")
        #expect(askedAgain)
        #expect(question.open == ScheduleQuestion.Shown(card: now, fingerprint: "two"))
        // Once only.
        question.close()
        let askedTwice = question.askAgain(now: now, fingerprint: "two")
        #expect(!askedTwice)
    }

    @Test func turnedDownForAChangeTheMacSentIsAskedAgain() {
        var question = ScheduleQuestion()
        question.ask(Self.scheduled, fingerprint: "one")
        let shown = question.open!
        question.close()
        let goes = question.turnOn(shown, now: Self.scheduled)
        #expect(goes)
        // The Mac sends what changed before it answers, so the card here is new by the time it is turned down.
        let now = Self.changed { $0.trigger?.minute = 45 }
        question.refused(shown, now: now, fingerprint: "two")
        let askedAgain = question.askAgain(now: now, fingerprint: "two")
        #expect(askedAgain)
    }

    @Test func aFingerprintThatMovedIsAskedAgainEvenIfTheCardLooksTheSame() {
        // A newer Mac may hold something of the schedule this device can't read: the Mac's fingerprint says it changed.
        var question = ScheduleQuestion()
        question.ask(Self.scheduled, fingerprint: "one")
        let shown = question.open!
        question.close()
        question.refused(shown, now: Self.scheduled, fingerprint: "two")
        let askedAgain = question.askAgain(now: Self.scheduled, fingerprint: "two")
        #expect(askedAgain)
    }

    @Test func turnedDownForAnotherReasonIsNotAskedAgain() {
        var question = ScheduleQuestion()
        question.ask(Self.scheduled, fingerprint: "one")
        let shown = question.open!
        question.close()
        question.refused(shown, now: Self.scheduled, fingerprint: "one")
        let askedAgain = question.askAgain(now: Self.scheduled, fingerprint: "one")
        #expect(!askedAgain)
        // Nor later, when the card changes for some other reason.
        let later = Self.changed { $0.command = "later" }
        let askedLater = question.askAgain(now: later, fingerprint: "three")
        #expect(!askedLater)
        // Nor when the schedule was taken away.
        let gone = Self.changed { $0.trigger = nil }
        question.refused(shown, now: gone, fingerprint: nil)
        let askedWithNoSchedule = question.askAgain(now: gone, fingerprint: nil)
        #expect(!askedWithNoSchedule)
    }
}
