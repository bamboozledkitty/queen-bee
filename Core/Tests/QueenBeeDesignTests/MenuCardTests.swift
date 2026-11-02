import Testing
@testable import QueenBeeDesign

/// Where the arrow keys land in a menu card.
@Suite struct MenuCardTests {
    private let enabled = [true, false, true]

    @Test func withNothingHighlightedDownStartsAtTheTopAndUpAtTheBottom() {
        #expect(MenuCardNavigation.move(from: nil, by: 1, enabled: enabled) == 0)
        #expect(MenuCardNavigation.move(from: nil, by: -1, enabled: enabled) == 2)
    }

    @Test func movingSkipsWhatCantBePicked() {
        #expect(MenuCardNavigation.move(from: 0, by: 1, enabled: enabled) == 2)
        #expect(MenuCardNavigation.move(from: 2, by: -1, enabled: enabled) == 0)
    }

    @Test func stopsAtEitherEnd() {
        #expect(MenuCardNavigation.move(from: 2, by: 1, enabled: enabled) == 2)
        #expect(MenuCardNavigation.move(from: 0, by: -1, enabled: enabled) == 0)
    }

    @Test func nothingUsableMeansNoRow() {
        #expect(MenuCardNavigation.move(from: nil, by: 1, enabled: [false]) == nil)
    }
}
