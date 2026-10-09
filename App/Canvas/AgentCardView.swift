import AppKit
import QueenBeeCore

/// An agent's card: its live terminal under the title, its session's state beside the name,
/// and a Start button while no session is running.
final class AgentCardView: CardView {
    private let stateBadge = BadgeLabel()
    /// Shown when the card's settings have changed and the running session doesn't have them yet.
    private let restartBadge = BadgeLabel()
    private let startButton = NSButton(title: "Start session", target: nil, action: nil)
    private let terminalHolder = FlippedView()
    private weak var terminal: NSView?
    private var stateText = ""

    override var overviewText: String { stateText }

    override init(card: Card) {
        super.init(card: card)
        titleBar.addSubview(stateBadge)
        titleBar.addSubview(restartBadge)
        restartBadge.toolTip = "This card's settings changed after its session started. Restart the session from its settings to apply them."

        terminalHolder.wantsLayer = true
        content.addSubview(terminalHolder)

        startButton.bezelStyle = .rounded
        startButton.font = Theme.mono(Theme.Size.body)
        startButton.target = self
        startButton.action = #selector(startSession)
        content.addSubview(startButton)
    }

    override var titleAccessories: [NSView] { [stateBadge, restartBadge] }

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
        let isWaiting = context.mark.arrivals > context.mark.passes && state == .idle
        let tone: BadgeLabel.Tone = switch state {
        case .working, .needsYou: .live
        case .failed, .exited: .fail
        case .idle: isWaiting ? .live : .plain
        case .notStarted, .starting: .plain
        }
        stateText = isWaiting ? "waiting" : state.label.lowercased()
        stateBadge.set(stateText, tone: tone)
        restartBadge.set(context.needsRestart ? "restart to apply" : "", tone: .live)
        let live = state != .notStarted && state != .exited
        startButton.isHidden = live
        startButton.title = state == .exited ? "Restart session" : "Start session"
        super.update(card: new, context: context)
    }

    override func layoutContent() {
        terminalHolder.frame = content.bounds
        // A few points of padding so text doesn't touch the card's edge or the resize corner.
        terminal?.frame = terminalHolder.bounds.insetBy(dx: 6, dy: 4)
        startButton.sizeToFit()
        startButton.frame.origin = CGPoint(x: (content.bounds.width - startButton.frame.width) / 2,
                                           y: (content.bounds.height - startButton.frame.height) / 2)
    }

    override func updateContentLayers() {
        terminalHolder.layer?.backgroundColor = Theme.terminal.cgColor
    }

    @objc private func startSession() {
        canvas?.controller?.startSession(forCard: card.id)
    }
}
