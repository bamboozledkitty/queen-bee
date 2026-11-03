import Testing
@testable import QueenBeeCore

struct PinSetTests {
    @Test func aPinIsPerProject() {
        var pins = PinSet()
        pins.toggle(project: "/a", id: "f")
        #expect(pins.contains(project: "/a", id: "f"))
        #expect(!pins.contains(project: "/b", id: "f"))
        pins.toggle(project: "/a", id: "f")
        #expect(!pins.contains(project: "/a", id: "f"))
    }

    @Test func anOldBarePinPinsEveryCopy() {
        let pins = PinSet(saved: ["f"])
        #expect(pins.contains(project: "/a", id: "f"))
        #expect(pins.contains(project: "/b", id: "f"))
        #expect(!pins.contains(project: "/a", id: "g"))
    }

    @Test func unpinningABarePinKeepsTheOtherCopies() {
        var pins = PinSet(saved: ["f"])
        pins.toggle(project: "/a", id: "f", otherProjects: ["/a", "/b"])
        #expect(!pins.contains(project: "/a", id: "f"))
        #expect(pins.contains(project: "/b", id: "f"))
    }

    @Test func savedPinsComeBack() {
        var pins = PinSet()
        pins.toggle(project: "/a", id: "f")
        let again = PinSet(saved: pins.saved)
        #expect(again == pins)
        #expect(again.ids == ["f"])
    }
}
