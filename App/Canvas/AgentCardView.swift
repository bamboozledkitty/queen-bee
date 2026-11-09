import AppKit
import QueenBeeCore
import QueenBeeDesign
import SwiftUI

/// The button on a card with no running session, in the design system's look. Its surface is solid, so the
/// terminal's text never shows through it. While a start is slow it also carries the advice, in a panel.
private struct StartPrompt: View {
    var title: String
    var note: String?
    var width: CGFloat
    var action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
        Group {
            if let note {
                // A slow start is a strip across the top, with the terminal pushed down below it, so it never
                // hides the question Claude Code is asking at the foot of the terminal.
                HStack(spacing: DS.Space.s) {
                    Text(note)
                        .textRole(.caption)
                        .foregroundStyle(Palette.textMuted.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s)
                    Button(title, action: action).buttonStyle(.ds(.secondary))
                }
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.xs)
                .frame(width: width)
                .background(Palette.raised.color, in: shape)
                .overlay(shape.strokeBorder(Palette.hairlineStrong.color, lineWidth: DS.Stroke.hairline))
            } else {
                Button(title, action: action).buttonStyle(.ds(.secondary))
            }
        }
    }
}

/// The strip over a card's terminal while it shows the card's stand-in in a rehearsal.
private struct StandInStrip: View {
    var body: some View {
        StatusPill(Rehearsal.standInLabel, tone: .neutral, dot: false)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs)
    }
}

/// An agent's card: its live terminal under the title, its session's state beside the name,
/// and a Start button while no session is running.
final class AgentCardView: CardView {
    private let stateBadge = BadgeLabel()
    /// Shown when the card's settings have changed and the running session doesn't have them yet.
    private let restartBadge = BadgeLabel()
    /// What the session cost in the run on show.
    private let costBadge = BadgeLabel()
    private let startButton = NSHostingView(rootView: StartPrompt(title: "Start agent", note: nil, width: 0, action: {}))
    private var startTitle = "Start agent"
    private let terminalHolder = FlippedView()
    private weak var terminal: NSView?
    /// Says the terminal below it is the card's stand-in's, in a rehearsal.
    private let standInStrip = NSHostingView(rootView: StandInStrip())
    /// The terminal is the card's stand-in's. The Start button acts on the card's own session, so it isn't offered.
    private var isStandIn = false
    private var stateText = ""
    /// The card's browser half, while its Browser switch is on.
    private(set) var browserPane: BrowserPaneView?
    private let browserRule = NSView()
    /// The Error output's row at the card's foot, below the terminal.
    private let errorRow = PortRowView()

    override var overviewText: String { stateText }

    override init(card: Card) {
        super.init(card: card)
        titleBar.addSubview(stateBadge)
        titleBar.addSubview(restartBadge)
        titleBar.addSubview(costBadge)
        costBadge.toolTip = "An estimate of what this agent's work cost in the run on show"
        restartBadge.toolTip = "You changed this agent's settings while it was running. Restart it from its settings to use them."

        terminalHolder.wantsLayer = true
        content.addSubview(terminalHolder)
        // Inside the terminal's holder, so it hides with the terminal when the canvas zooms out to the overview.
        standInStrip.isHidden = true
        terminalHolder.addSubview(standInStrip)

        content.addSubview(startButton)
        content.addSubview(errorRow)

        browserRule.wantsLayer = true
        browserRule.isHidden = true
        content.addSubview(browserRule)
    }

    /// Shows the card's browser beside its terminal, or takes it away. `tab` is nil when the card has none.
    func attach(browser tab: BrowserTab?) {
        guard browserPane?.tab !== tab else { return }
        browserPane?.letGo()
        browserPane?.removeFromSuperview()
        browserPane = tab.map { BrowserPaneView(tab: $0) }
        if let browserPane { content.addSubview(browserPane, positioned: .below, relativeTo: browserRule) }
        browserRule.isHidden = browserPane == nil
        needsLayout = true
        updateBrowserVisibility()
    }

    /// The canvas scrolled or zoomed. A browser that can't be seen, or is too small to read, stops streaming.
    func updateBrowserVisibility() {
        guard let browserPane else { return }
        browserPane.isInView = zoom >= Self.overviewBelow && !browserPane.visibleRect.isEmpty
    }

    override var zoom: CGFloat {
        didSet {
            updateBrowserVisibility()
            // Under the overview the terminal can't be seen, and drawing it is the costliest part of a card.
            // Its session runs on and keeps what it prints, so it is whole again when the canvas zooms back in.
            let covered = zoom < Self.overviewBelow
            if terminalHolder.isHidden != covered { terminalHolder.isHidden = covered }
        }
    }

    override func removeFromSuperview() {
        browserPane?.letGo()
        super.removeFromSuperview()
    }

    override var titleAccessories: [NSView] { [stateBadge, costBadge, restartBadge] }

    func attach(terminal view: NSView) {
        guard terminal !== view else { return }
        terminal?.removeFromSuperview()
        terminal = view
        terminalHolder.addSubview(view)
        needsLayout = true
    }

    override func update(card new: Card, context: CardContext) {
        let state = context.sessionState
        // In a run, an agent that has been handed work but hasn't started on it yet is waiting.
        let isWaiting = context.isRunning && context.mark.arrivals > context.mark.passes && state == .idle
        let tone: BadgeLabel.Tone = switch state {
        case .working, .needsYou: .live
        case .failed, .exited: .fail
        case .idle: isWaiting ? .live : .plain
        case .notStarted, .starting: .plain
        }
        // An agent that asked a question is idle, but the run is owed its reply.
        let asked = state == .idle ? context.waiting : nil
        stateText = asked ?? (isWaiting ? "waiting" : context.isSlowToStart ? "starting is taking a while" : state.label.lowercased())
        stateBadge.set(stateText, tone: asked == nil ? tone : .live)
        stateBadge.toolTip = context.isSlowToStart
            ? "Claude Code hasn't said it's ready yet. Look in the terminal in case it's asking you something, such as whether to trust this folder. If it's stuck, press Retry."
            : nil
        restartBadge.set(context.needsRestart ? "restart to apply" : "", tone: .live)
        costBadge.set(context.cost ?? "", tone: .plain)
        let live = state != .notStarted && state != .exited
        // A turn that ended with an error leaves the session going, and it can be typed to, or restarted.
        lastTurnFailed = state == .failed && !context.isSlowToStart && !context.isStandIn
        if isStandIn != context.isStandIn {
            isStandIn = context.isStandIn
            standInStrip.isHidden = !isStandIn
            needsLayout = true
        }
        startButton.isHidden = isStandIn || (live && !context.isSlowToStart && !lastTurnFailed)
        startTitle = context.isSlowToStart ? "Retry" : state == .exited || lastTurnFailed ? "Restart agent" : "Start agent"
        startButton.toolTip = context.isSlowToStart ? "Stop this agent's Claude Code and start it again"
            : lastTurnFailed ? "Stop this agent's Claude Code and start it again, carrying on its conversation" : nil
        isSlowToStart = context.isSlowToStart && !context.isStandIn
        errorRow.set(name: portLabel("error"), count: context.mark.ports["error"] ?? 0,
                     isLatest: context.mark.lastPort == "error", isRunning: context.isRunning)
        super.update(card: new, context: context)
    }

    /// While a slow start is shown, the note and Retry sit in a strip above the terminal, which may be asking something.
    private var isSlowToStart = false
    /// So do a note and Restart agent after a turn that ended with an error, which the terminal shows.
    private var lastTurnFailed = false

    override func layoutContent() {
        // The Error row takes the foot. Above it, with a browser, the card is split down the middle: terminal on
        // the left, page on the right.
        let foot = CanvasGeometry.portRowHeight
        let above = max(0, content.bounds.height - foot)
        errorRow.frame = NSRect(x: 1, y: above, width: max(0, content.bounds.width - 2), height: foot)
        var left = CGRect(x: 0, y: 0, width: content.bounds.width, height: above)
        if let browserPane {
            left.size.width = (content.bounds.width / 2).rounded()
            browserRule.frame = CGRect(x: left.maxX, y: 0, width: 1, height: above)
            browserPane.frame = CGRect(x: left.maxX + 1, y: 0, width: content.bounds.width - left.maxX - 1, height: above)
        }
        terminalHolder.frame = left
        let inStrip = isSlowToStart || lastTurnFailed
        // A few points of padding so text doesn't touch the card's edge or the resize corner.
        let note = isSlowToStart ? "Claude Code may be asking whether to trust this folder. Answer in the terminal below, or press Retry if it is stuck."
            : lastTurnFailed ? "Its last turn ended with an error. Type to it below, or restart it." : nil
        startButton.rootView = StartPrompt(title: startTitle, note: note, width: max(0, left.width - 2 * DS.Space.s)) { [weak self] in
            self?.startSession()
        }
        startButton.frame.size = startButton.fittingSize
        startButton.frame.origin = CGPoint(x: left.minX + (left.width - startButton.frame.width) / 2,
                                           y: inStrip ? DS.Space.xs : (left.height - startButton.frame.height) / 2)
        // The strip sits above the terminal, not over it, so the foot of the terminal stays in view.
        var area = terminalHolder.bounds.insetBy(dx: 6, dy: 4)
        if inStrip {
            let strip = startButton.frame.maxY + DS.Space.xs
            area.origin.y = max(area.origin.y, strip)
            area.size.height = max(0, terminalHolder.bounds.height - 4 - area.origin.y)
        }
        if isStandIn {
            standInStrip.frame = CGRect(origin: .zero, size: standInStrip.fittingSize)
            area.origin.y = max(area.origin.y, standInStrip.frame.maxY)
            area.size.height = max(0, terminalHolder.bounds.height - 4 - area.origin.y)
        }
        terminal?.frame = area
        updateBrowserVisibility()
    }

    override func updateContentLayers() {
        terminalHolder.layer?.backgroundColor = Theme.Canvas.terminal.cgColor
        browserRule.layer?.backgroundColor = Theme.Canvas.rule.cgColor
    }

    private func startSession() {
        canvas?.controller?.startSession(forCard: card.id)
    }
}
