import AppKit
import SwiftUI

/// The flow's orchestrator: a live Claude Code session docked beside the canvas, so it
/// stays in reach wherever the canvas is panned.
struct OrchestratorPane: View {
    let controller: FlowController

    var body: some View {
        let session = controller.orchestrator
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(nsColor: session.state.color))
                    .frame(width: 8, height: 8)
                Text("Orchestrator")
                    .font(.headline)
                Text(session.state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.state == .exited || session.state == .notStarted {
                    Button(session.state == .exited ? "Restart" : "Start") { controller.startOrchestrator() }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            TerminalHost(terminal: session.view)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(nsColor: Palette.terminalBackground))
        }
    }
}

/// Puts a session's terminal view into SwiftUI. The view belongs to the session, so this
/// only re-parents it.
struct TerminalHost: NSViewRepresentable {
    let terminal: NSView

    func makeNSView(context: Context) -> NSView {
        let holder = NSView()
        attach(to: holder)
        return holder
    }

    func updateNSView(_ holder: NSView, context: Context) {
        attach(to: holder)
    }

    private func attach(to holder: NSView) {
        guard terminal.superview !== holder else { return }
        holder.subviews.forEach { $0.removeFromSuperview() }
        terminal.frame = holder.bounds
        terminal.autoresizingMask = [.width, .height]
        holder.addSubview(terminal)
    }
}
