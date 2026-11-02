import Foundation
import Testing
@testable import QueenBeeCore

/// A schedule's time is written the way the Mac writes times, except for what the orchestrator reads.
@Suite struct TriggerTimeTests {
    private let twelve = Locale(identifier: "en_US")
    private let twentyFour = Locale(identifier: "en_GB")

    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    @Test func aDailySummaryFollowsTheTwelveHourSetting() {
        let trigger = Trigger(kind: .daily, hour: 7, minute: 30)
        #expect(plain(trigger.summary(in: twelve)) == "Every day at 7:30 AM")
        #expect(plain(Trigger(kind: .daily, hour: 19, minute: 5).summary(in: twelve)) == "Every day at 7:05 PM")
    }

    @Test func aDailySummaryFollowsTheTwentyFourHourSetting() {
        #expect(Trigger(kind: .daily, hour: 7, minute: 30).summary(in: twentyFour) == "Every day at 07:30")
        #expect(Trigger(kind: .daily, hour: 19, minute: 5).summary(in: twentyFour) == "Every day at 19:05")
    }

    @Test func aWeeklySummaryFollowsTheSetting() {
        let trigger = Trigger(kind: .weekly, hour: 18, minute: 0, weekdays: [2, 4])
        #expect(plain(trigger.summary(in: twelve)) == "Mon, Wed at 6:00 PM")
        #expect(trigger.summary(in: twentyFour) == "Mon, Wed at 18:00")
    }

    @Test func theOrchestratorsSummaryStaysTwentyFourHour() {
        #expect(Trigger(kind: .daily, hour: 19, minute: 5).summary == "Every day at 19:05")
    }

    @Test func intervalsDoNotMentionTime() {
        #expect(Trigger(kind: .interval, minutes: 30).summary(in: twelve) == "Every 30 minutes")
    }

    @Test func knowsWhetherALocaleUsesTwentyFourHours() {
        #expect(!Trigger.usesTwentyFourHours(twelve))
        #expect(Trigger.usesTwentyFourHours(twentyFour))
    }

    @Test func hourLabelsFollowTheSetting() {
        #expect(plain(Trigger.hourLabel(0, in: twelve)) == "12 AM")
        #expect(plain(Trigger.hourLabel(15, in: twelve)) == "3 PM")
        #expect(Trigger.hourLabel(15, in: twentyFour) == "15")
    }
}
