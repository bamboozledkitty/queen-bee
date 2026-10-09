import AppKit
import QueenBeeCore

/// An agent's card: its live terminal under the title, a state dot beside the name,
/// and a Start button while no session is running.
final class AgentCardView: CardView {
    private let stateDot = FlippedView()
    private let stateLabel = NSTextField(labelWithString: "")
    private let startButton = NSButton(title: "Start session", target: nil, action: nil)
    private let terminalHolder = FlippedView()
    private weak var terminal: NSView?
    private var isFocused = false

    override init(card: Card) {
        super.init(card: card)
        stateDot.wantsLayer = true
        stateDot.layer?.cornerRadius = 4
        titleBar.addSubview(stateDot)
        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.alignment = .right
        titleBar.addSubview(stateLabel)

        terminalHolder.wantsLayer = true
        terminalHolder.layer?.backgroundColor = Palette.terminalBackground.cgColor
        content.addSubview(terminalHolder)

        startButton.bezelStyle = .rounded
        startButton.target = self
        startButton.action = #selector(startSession)
        content.addSubview(startButton)
    }

    override var titleTrailingInset: CGFloat { 110 }

    func attach(terminal view: NSView) {
        guard terminal !== view else { return }
        terminal?.removeFromSuperview()
        terminal = view
        terminalHolder.addSubview(view)
        needsLayout = true
    }

    override func update(card new: Card, context: CardContext) {
        super.update(card: new, context: context)
        isFocused = context.isFocused
        stateDot.layer?.backgroundColor = context.sessionState.color.cgColor
        stateLabel.stringValue = context.sessionState.label
        let live = context.sessionState != .notStarted && context.sessionState != .exited
        startButton.isHidden = live
        startButton.title = context.sessionState == .exited ? "Restart session" : "Start session"
        if context.isFocused {
            body.layer?.borderColor = Palette.accent.cgColor
            body.layer?.borderWidth = 3
        }
    }

    override func layoutContent() {
        stateDot.frame = NSRect(x: titleBar.bounds.width - 20, y: 11, width: 8, height: 8)
        stateLabel.frame = NSRect(x: titleBar.bounds.width - 110, y: 8, width: 84, height: 14)
        terminalHolder.frame = content.bounds
        // A few points of padding so text doesn't touch the card's edge or the resize corner.
        terminal?.frame = terminalHolder.bounds.insetBy(dx: 6, dy: 4)
        startButton.sizeToFit()
        startButton.frame.origin = CGPoint(x: (content.bounds.width - startButton.frame.width) / 2,
                                           y: (content.bounds.height - startButton.frame.height) / 2)
    }

    @objc private func startSession() {
        canvas?.controller?.startSession(forCard: card.id)
    }
}
