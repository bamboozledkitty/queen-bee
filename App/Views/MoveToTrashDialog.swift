import QueenBeeDesign
import SwiftUI

extension View {
    /// Asks before a flow goes to the Trash, and moves it there when the person agrees. Set `flow` to ask.
    func movesToTrash(_ flow: Binding<FlowController?>) -> some View {
        confirmationDialog("Move \"\(flow.wrappedValue?.flow.name ?? "")\" to the Trash?",
                           isPresented: .init(get: { flow.wrappedValue != nil }, set: { if !$0 { flow.wrappedValue = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let deleting = flow.wrappedValue, !deleting.project.delete(deleting, toTrash: true) {
                    deleting.banner = "Couldn't move \"\(deleting.flow.name)\" to the Trash, so it is still here."
                }
                flow.wrappedValue = nil
            }
        } message: {
            let usedBy = flow.wrappedValue?.runByOthersLine.map { "\n\n" + $0 } ?? ""
            Text("Its agents are stopped and the flow's file goes to the Trash, so you can put it back from there with its run history. What the agents said stays in Claude Code's history." + usedBy)
        }
    }
}
