import Testing
@testable import QueenBeeDesign

@Suite struct MotionTests {
    @Test func withReduceMotionTheChangeHappensAtOnce() {
        #expect(DS.Motion.resolved(DS.Motion.standard, reduceMotion: true) == nil)
        #expect(DS.Motion.resolved(DS.Motion.quick, reduceMotion: true) == nil)
    }

    @Test func withoutItTheCurveIsUnchanged() {
        #expect(DS.Motion.resolved(DS.Motion.standard, reduceMotion: false) == DS.Motion.standard)
        #expect(DS.Motion.resolved(DS.Motion.quick, reduceMotion: false) == DS.Motion.quick)
    }
}
