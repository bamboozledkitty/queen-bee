import Testing
@testable import QueenBeeCore

struct PinSetTests {
    @Test func aCopiedFlowIsPinnedPerProject() {
        var pins = PinSet()
        pins.toggle(project: "/a", id: "f", otherProjects: ["/a", "/b"])
        #expect(pins.contains(project: "/a", id: "f"))
        #expect(!pins.contains(project: "/b", id: "f"))
        pins.toggle(project: "/a", id: "f", otherProjects: ["/a", "/b"])
        #expect(!pins.contains(project: "/a", id: "f"))
    }

    @Test func aFlowInOneProjectIsPinnedByItsIdSoAMovedFolderKeepsIt() {
        var pins = PinSet()
        pins.toggle(project: "/a", id: "f", otherProjects: ["/a"])
        #expect(pins.saved == ["f"])
        #expect(pins.contains(project: "/moved", id: "f"))
        pins.toggle(project: "/moved", id: "f", otherProjects: ["/moved"])
        #expect(pins.saved.isEmpty)
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
        pins.toggle(project: "/a", id: "f", otherProjects: ["/b"])
        let again = PinSet(saved: pins.saved)
        #expect(again == pins)
        #expect(again.ids == ["f"])
    }
}
