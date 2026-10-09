import QueenBeeCore
import SwiftUI
import UniformTypeIdentifiers

/// The card types, floating at the canvas's corner. Click one to add it at the middle of
/// what's on screen, or drag it to where you want it.
struct PaletteView: View {
    static let width: CGFloat = 132
    let controller: FlowController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CardKindMenu.kinds, id: \.self) { kind in
                PaletteRow(kind: kind) { controller.addCard(kind) }
                if kind == .agent {
                    Rectangle().fill(Theme.hairline.ui).frame(height: 1).padding(.vertical, 3)
                }
            }
        }
        .padding(Theme.Space.xs)
        .frame(width: Self.width)
        .floatingPanel()
    }
}

private struct PaletteRow: View {
    let kind: CardKind
    let add: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: CanvasGeometry.icon(for: kind))
                .font(.system(size: 11, weight: .medium))
                .frame(width: 16)
            Text(kind.label)
                .font(.dsMono(Theme.Size.caption, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, 5)
        .background(isHovered ? Theme.barHover.ui : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: add)
        .onDrag {
            // A type of the app's own, so a terminal under the pointer leaves the drop for the canvas.
            let provider = NSItemProvider()
            let type = CanvasDocumentView.cardKindType.rawValue
            provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .ownProcess) { done in
                done(Data(kind.rawValue.utf8), nil)
                return nil
            }
            return provider
        }
        .help("Click to add a \(kind.label) card, or drag it onto the canvas")
        .animation(Theme.Motion.quick, value: isHovered)
    }
}

/// Zoom out, the zoom level, zoom in, and fit, pinned to the canvas's corner.
struct ZoomPill: View {
    let controller: FlowController

    var body: some View {
        HStack(spacing: 2) {
            button("minus", help: "Zoom out") { controller.canvas?.zoom(by: 0.8) }
            Button { controller.canvas?.zoomToActualSize() } label: {
                Text("\(Int((controller.zoom * 100).rounded()))%")
                    .font(.dsMono(Theme.Size.caption, .medium))
                    .frame(width: 40)
            }
            .buttonStyle(.plain)
            .help("Back to 100%")
            button("plus", help: "Zoom in") { controller.canvas?.zoom(by: 1.25) }
            Rectangle().fill(Theme.hairline.ui).frame(width: 1, height: 14).padding(.horizontal, 2)
            button("arrow.up.left.and.arrow.down.right", help: "Fit the whole flow") { controller.canvas?.zoomToFit() }
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .floatingPanel()
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// The run's latest step in one line. Click it for the whole log.
struct StatusStrip: View {
    let controller: FlowController
    let showLog: () -> Void

    var body: some View {
        if let last = controller.log.last {
            Button(action: showLog) {
                HStack(spacing: Theme.Space.s) {
                    Circle()
                        .fill((controller.isRunning ? Theme.live : Theme.inkSecondary).ui)
                        .frame(width: 6, height: 6)
                    Text(last.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if controller.handOffs > 0 {
                        Text("\(controller.handOffs) hand-offs")
                            .foregroundStyle(Theme.inkSecondary.ui)
                            .contentTransition(.numericText())
                    }
                }
                .font(.dsMono(Theme.Size.caption))
                .foregroundStyle(Theme.ink.ui)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 5)
                .frame(maxWidth: 460, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .floatingPanel()
            .help("Show the run log")
            .animation(Theme.Motion.standard, value: controller.handOffs)
        }
    }
}

/// A one-line message about something that didn't work. Click to dismiss.
struct BannerView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        Text(text)
            .font(.dsSans(Theme.Size.body))
            .foregroundStyle(Theme.failInk.ui)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 6)
            .background(Theme.failTint.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.failInk.ui, lineWidth: Theme.Stroke.card))
            .frame(maxWidth: 520)
            .onTapGesture(perform: dismiss)
            .help("Click to dismiss")
    }
}

/// What an empty flow shows: a short note beside the orchestrator, pointing at it. The
/// orchestrator is where a flow gets described, so the note sends you there and stays out
/// of the canvas's way.
struct OrchestratorCallout: View {
    let controller: FlowController
    /// The orchestrator's terminal is on screen for the arrow to point at.
    let orchestratorIsShowing: Bool
    let showOrchestrator: () -> Void
    @State private var nudged = false

    var body: some View {
        let session = controller.orchestrator
        let isOff = session.state == .notStarted || session.state == .exited
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Describe the flow you want")
                        .font(.dsMono(Theme.Size.body, .medium))
                    Spacer(minLength: Theme.Space.s)
                    Button { AppServices.shared.dismissHint(forFlow: controller.flow.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .help("Build it by hand")
                }
                Text(isOff ? "The orchestrator builds it on the canvas, but its session isn't running."
                           : "Tell the orchestrator and it builds it here. Or drag cards in from the palette.")
                    .font(.dsSans(Theme.Size.caption))
                    .foregroundStyle(Theme.inkSecondary.ui)
                    .fixedSize(horizontal: false, vertical: true)
                if isOff {
                    Button("Start the orchestrator") {
                        controller.startOrchestrator()
                        showOrchestrator()
                    }
                    .buttonStyle(.panel())
                    .padding(.top, 3)
                } else if !orchestratorIsShowing {
                    Button("Show the orchestrator", action: showOrchestrator)
                        .buttonStyle(.panel())
                        .padding(.top, 3)
                }
            }
            .foregroundStyle(Theme.ink.ui)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 9)
            .frame(width: 250, alignment: .leading)
            .floatingPanel()

            if orchestratorIsShowing, !isOff {
                // The arrow reaches across the gap to the panel, and leans toward it now and then.
                Arrow()
                    .stroke(Theme.ink.ui, style: StrokeStyle(lineWidth: Theme.Stroke.link, lineCap: .round, lineJoin: .round))
                    .frame(width: 30, height: 12)
                    .offset(x: nudged ? 4 : 0)
                    .onAppear {
                        guard Theme.Motion.isAllowed else { return }
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { nudged = true }
                    }
            }
        }
    }

    private struct Arrow: Shape {
        nonisolated func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            path.move(to: CGPoint(x: rect.maxX - 8, y: rect.minY + 1))
            path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.maxY - 1))
            return path
        }
    }
}
