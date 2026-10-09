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

/// What a new flow shows: one box to say what you want built, sent to the orchestrator.
struct BlankFlowPrompt: View {
    let controller: FlowController
    let showOrchestrator: () -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && controller.orchestrator.isLive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Describe the flow you want")
                    .font(.dsMono(Theme.Size.heading, .medium))
                Spacer()
                Button { controller.promptDismissed = true } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Build it by hand")
            }
            TextField("A writer and a reviewer that loop until the review approves", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(.dsSans(Theme.Size.title))
                .padding(Theme.Space.s)
                .background(Theme.bar.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.hairline.ui))
                .focused($isFocused)
                .onSubmit(send)
            HStack {
                Text("The orchestrator builds it on the canvas. Or drag cards in from the palette.")
                    .font(.dsSans(Theme.Size.caption))
                    .foregroundStyle(Theme.inkSecondary.ui)
                Spacer()
                Button("Build it", action: send)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSend)
            }
        }
        .foregroundStyle(Theme.ink.ui)
        .padding(Theme.Space.l)
        .frame(width: 460)
        .floatingPanel()
    }

    private func send() {
        guard canSend else { return }
        controller.orchestrator.send("Build this flow on the canvas with your tools, then tell me what you made: " + text)
        controller.promptDismissed = true
        showOrchestrator()
    }
}
