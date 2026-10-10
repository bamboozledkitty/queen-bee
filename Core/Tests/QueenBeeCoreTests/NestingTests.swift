import Foundation
import Testing
@testable import QueenBeeCore

@Suite struct NestingTests {
    /// A chain of flows, each running the next by name, with the first's limit set.
    private func chain(_ count: Int, limit: Int? = nil) -> [Flow] {
        (0..<count).map { n in
            var flow = Flow(id: "f\(n)", name: "Level\(n)")
            if n == 0 { flow.subflowLimit = limit }
            if n + 1 < count {
                var patch = CardPatch()
                patch.flowRef = "Level\(n + 1)"
                _ = try? flow.addCard(kind: .flow, name: "Next", patch: patch)
            }
            return flow
        }
    }

    @Test func levelsCountDownFromTheTopFlowsLimit() {
        let nesting = Nesting(flows: chain(5))
        #expect(nesting.levelsLeft("f0") == 3)
        #expect(nesting.levelsLeft("f3") == 0)
        #expect(nesting.levelsLeft("f4") == -1)
        #expect(nesting.levelsBelow("f0") == 4)
        #expect(nesting.topFlows(of: "f4") == ["f0"])
        #expect(nesting.subflows(of: "f1").map(\.id) == ["f2", "f3", "f4"])
    }

    @Test func theTopFlowsLimitIsTheOneThatCounts() {
        let nesting = Nesting(flows: chain(3, limit: 1))
        #expect(nesting.levelsLeft("f1") == 0)
        #expect(nesting.problemAddingSubflow(to: "f1")?.contains("Level0 allows sub-flows 1 level deep") == true)
        #expect(nesting.problem(placing: "f2", in: "f1")?.contains("deeper") == true)
        #expect(Nesting.clamped(40) == 10 && Nesting.clamped(nil) == 3 && Nesting.clamped(-2) == 0)
    }

    @Test func aFlowCantRunItselfOrGoRoundInACircle() {
        var flows = chain(3)
        var patch = CardPatch()
        patch.flowRef = "f0"
        _ = try? flows[2].addCard(kind: .flow, name: "Back", patch: patch)
        let nesting = Nesting(flows: flows)
        #expect(nesting.problem(placing: "f0", in: "f0") == "A flow can't run itself.")
        #expect(nesting.problem(placing: "f0", in: "f2")?.contains("round for ever") == true)
        // A circle in the files still answers: the way back counts as one more step, then stops.
        #expect(nesting.levelsBelow("f0") == 3)
        #expect(nesting.levelsLeft("f2") == 1)
    }

    @Test func aFlowRunByTwoParentsGoesByTheStricter() {
        var flows = chain(2, limit: 3)
        var loose = Flow(id: "loose", name: "Loose")
        loose.subflowLimit = 1
        var patch = CardPatch()
        patch.flowRef = "f1"
        _ = try? loose.addCard(kind: .flow, name: "Also", patch: patch)
        flows.append(loose)
        #expect(Nesting(flows: flows).levelsLeft("f1") == 0)
    }

    @Test func denseReferencesStillAnswerQuickly() {
        // Every flow runs every other one. Walking each path would take for ever.
        var flows = (0..<14).map { Flow(id: "d\($0)", name: "Dense\($0)") }
        for i in flows.indices {
            for j in flows.indices where i != j {
                var patch = CardPatch()
                patch.flowRef = "d\(j)"
                _ = try? flows[i].addCard(kind: .flow, name: "To\(j)", patch: patch)
            }
        }
        let began = Date()
        let nesting = Nesting(flows: flows)
        for flow in flows { _ = nesting.levelsLeft(flow.id); _ = nesting.levelsBelow(flow.id); _ = nesting.topFlows(of: flow.id) }
        #expect(Date().timeIntervalSince(began) < 1)
    }
}
