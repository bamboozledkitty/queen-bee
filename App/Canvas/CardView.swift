import AppKit
import QueenBeeCore

/// A round dot on a card's edge that a link starts from or lands on.
final class PortDotView: NSView {
    let port: String
    let isOutput: Bool
    var isLinked = false { didSet { needsDisplay = true } }
    private var isHovered = false { didSet { needsDisplay = true } }

    init(port: String, isOutput: Bool) {
        self.port = port
        self.isOutput = isOutput
        let d = CanvasGeometry.portRadius * 2 + 6
        super.init(frame: NSRect(x: 0, y: 0, width: d, height: d))
        toolTip = isOutput ? "\(portLabel(port)): drag to another card to link" : "Input"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // An output grows a little under the pointer, to say it can be dragged from.
        let r = CanvasGeometry.portRadius + (isHovered && isOutput ? 1.5 : 0)
        let circle = NSRect(x: bounds.midX - r, y: bounds.midY - r, width: r * 2, height: r * 2)
        let path = NSBezierPath(ovalIn: circle)
        (isLinked || isHovered ? Theme.ink : Theme.surface).setFill()
        path.fill()
        Theme.ink.setStroke()
        path.lineWidth = Theme.Stroke.card
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func resetCursorRects() {
        if isOutput { addCursorRect(bounds, cursor: .crosshair) }
    }
}

/// The strip you drag a card by. It shows the open hand under the pointer, and tints a
/// little, so it reads as something to grab.
final class TitleBarView: NSView {
    var isHovered = false { didSet { if isHovered != oldValue { superview?.superview?.needsDisplay = true } } }
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}

/// A small tinted label in a card's title bar: a state, a count, a check.
final class BadgeLabel: NSView {
    enum Tone { case plain, live, pass, fail }

    private let label = NSTextField(labelWithString: "")
    private(set) var tone: Tone = .plain

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Radius.badge
        label.font = Theme.mono(Theme.Size.caption, .medium)
        addSubview(label)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, tone: Tone) {
        self.tone = tone
        if label.stringValue != text { label.stringValue = text }
        isHidden = text.isEmpty
        label.textColor = switch tone {
        case .plain: Theme.inkSecondary
        case .live: Theme.liveInk
        case .pass: Theme.passInk
        case .fail: Theme.failInk
        }
        label.sizeToFit()
        setFrameSize(NSSize(width: label.frame.width + 10, height: 16))
        label.setFrameOrigin(NSPoint(x: 5, y: (16 - label.frame.height) / 2))
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = switch tone {
        case .plain: NSColor.clear.cgColor
        case .live: Theme.liveTint.cgColor
        case .pass: Theme.passTint.cgColor
        case .fail: Theme.failTint.cgColor
        }
    }
}

/// What a link being dragged would do if dropped on a card.
enum LinkDrop {
    case none, accepts, refuses
}

/// A card on the canvas: a title bar to drag it by, dots for its links, a corner to resize it.
/// Its frame is the card's rectangle widened by `gutter` on each side, so the dots that
/// straddle the card's edges stay inside the view and can be clicked.
class CardView: NSView {
    static let gutter: CGFloat = CanvasGeometry.portRadius + 3
    /// As far left or up as a card may be dragged: just inside the canvas's edge.
    static let farLeft: CGFloat = -CanvasView.margin + 100

    private(set) var card: Card
    private(set) var context = CardContext()
    weak var canvas: CanvasView?

    let body = FlippedView()
    let titleBar = TitleBarView()
    let content = FlippedView()
    private let titleRule = FlippedView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let runBadge = BadgeLabel()
    private let resizeGrip = ResizeGripView()
    private var inputDot: PortDotView?
    private var outputDots: [PortDotView] = []
    private var dragOrigin = CGPoint.zero
    private var dragSize = CGSize.zero
    var linkDrop: LinkDrop = .none { didSet { if linkDrop != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    init(card: Card) {
        self.card = card
        super.init(frame: CardView.frame(for: card))
        wantsLayer = true

        body.wantsLayer = true
        body.layer?.cornerRadius = Theme.Radius.card
        body.layer?.masksToBounds = true
        addSubview(body)

        titleBar.wantsLayer = true
        titleRule.wantsLayer = true
        body.addSubview(titleBar)
        body.addSubview(content)
        body.addSubview(titleRule)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = Theme.ink
        titleBar.addSubview(iconView)
        nameLabel.font = Theme.mono(Theme.Size.body, .medium)
        nameLabel.textColor = Theme.ink
        nameLabel.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(nameLabel)
        titleBar.addSubview(runBadge)

        addSubview(resizeGrip)

        let move = NSPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        titleBar.addGestureRecognizer(move)
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        titleBar.addGestureRecognizer(click)
        let double = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        double.numberOfClicksRequired = 2
        titleBar.addGestureRecognizer(double)
        resizeGrip.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handleResize(_:))))

        rebuildPorts()
        applyCard()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    static func frame(for card: Card) -> CGRect {
        CanvasGeometry.frame(of: card).insetBy(dx: -gutter, dy: 0)
    }

    /// Brings the view in line with the model. Subclasses add their own state on top.
    func update(card new: Card, context: CardContext) {
        let portsChanged = ports(of: new) != ports(of: card) || acceptsInput(new) != acceptsInput(card)
        card = new
        self.context = context
        let target = CardView.frame(for: new)
        if frame != target { frame = target }
        if portsChanged { rebuildPorts() }
        applyCard()

        inputDot?.isLinked = context.linkedInputs
        for dot in outputDots { dot.isLinked = context.linkedPorts.contains(dot.port) }

        let mark = context.mark
        if mark.failed {
            runBadge.set("✕", tone: .fail)
        } else if runCount > 0 {
            runBadge.set(runCount > 1 ? "✓ \(runCount)" : "✓", tone: .pass)
        } else {
            runBadge.set("", tone: .plain)
        }
        needsLayout = true
        needsDisplay = true
    }

    /// How many times the run has passed through this card. An End counts what reached it;
    /// every other card counts what left it.
    var runCount: Int {
        card.kind == .end ? context.mark.arrivals : context.mark.passes
    }

    private func applyCard() {
        nameLabel.stringValue = card.name
        iconView.image = NSImage(systemSymbolName: CanvasGeometry.icon(for: card.kind), accessibilityDescription: card.kind.label)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        setAccessibilityLabel("\(card.kind.label) card \(card.name)")
        setAccessibilityIdentifier("card-\(card.id)")
    }

    private func rebuildPorts() {
        inputDot?.removeFromSuperview()
        outputDots.forEach { $0.removeFromSuperview() }
        inputDot = nil
        outputDots = []
        if acceptsInput(card) {
            let dot = PortDotView(port: "in", isOutput: false)
            addSubview(dot)
            inputDot = dot
        }
        for port in ports(of: card) {
            let dot = PortDotView(port: port, isOutput: true)
            dot.addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(handleLinkDrag(_:))))
            addSubview(dot)
            outputDots.append(dot)
        }
        addSubview(resizeGrip) // keep the grip above everything
    }

    override func layout() {
        super.layout()
        let g = CardView.gutter
        body.frame = NSRect(x: g, y: 0, width: bounds.width - g * 2, height: bounds.height)
        titleBar.frame = NSRect(x: 0, y: 0, width: body.bounds.width, height: CanvasGeometry.titleHeight)
        titleRule.frame = NSRect(x: 0, y: CanvasGeometry.titleHeight - 1, width: body.bounds.width, height: 1)
        content.frame = NSRect(x: 0, y: CanvasGeometry.titleHeight, width: body.bounds.width,
                               height: body.bounds.height - CanvasGeometry.titleHeight)
        iconView.frame = NSRect(x: 9, y: 7, width: 14, height: 14)

        // Badges sit at the title's right, the run badge outermost; the name takes what is left.
        var right = titleBar.bounds.width - 8
        for badge in [runBadge] + titleAccessories where !badge.isHidden {
            badge.setFrameOrigin(NSPoint(x: right - badge.frame.width, y: (CanvasGeometry.titleHeight - badge.frame.height) / 2))
            right = badge.frame.minX - 5
        }
        nameLabel.frame = NSRect(x: 29, y: 6, width: max(0, right - 29), height: 16)

        let origin = CGPoint(x: card.x - g, y: card.y)
        if let dot = inputDot { place(dot, at: CanvasGeometry.inputPoint(of: card), origin: origin) }
        for dot in outputDots { place(dot, at: CanvasGeometry.outputPoint(of: card, port: dot.port), origin: origin) }
        let s = CanvasGeometry.resizeHandle
        resizeGrip.frame = NSRect(x: bounds.width - g - s, y: bounds.height - s, width: s, height: s)
        layoutContent()
    }

    /// Extra badges a subclass shows in the title bar, right to left after the run badge.
    var titleAccessories: [NSView] { [] }

    /// Subclasses lay out what sits under the title.
    func layoutContent() {}

    private func place(_ dot: PortDotView, at point: CGPoint, origin: CGPoint) {
        dot.frame.origin = CGPoint(x: point.x - origin.x - dot.bounds.width / 2, y: point.y - origin.y - dot.bounds.height / 2)
    }

    // MARK: Colour

    /// The outline says the most pressing thing about the card: a link is about to land,
    /// it is selected, it failed, it is live, or nothing in particular.
    var outline: (color: NSColor, width: CGFloat) {
        switch linkDrop {
        case .accepts: return (Theme.live, Theme.Stroke.selected)
        case .refuses: return (Theme.failInk, Theme.Stroke.selected)
        case .none: break
        }
        if context.isFocused || context.isSelected { return (Theme.select, Theme.Stroke.selected) }
        if context.mark.failed { return (Theme.failInk, Theme.Stroke.link) }
        if context.isLive { return (Theme.live, Theme.Stroke.link) }
        return (Theme.ink, Theme.Stroke.card)
    }

    override var wantsUpdateLayer: Bool { true }

    // Layer colours are set here because this runs with the view's own light or dark
    // appearance in force, so they follow a change of mode.
    override func updateLayer() {
        body.layer?.backgroundColor = Theme.surface.cgColor
        body.layer?.borderColor = outline.color.cgColor
        body.layer?.borderWidth = outline.width
        titleBar.layer?.backgroundColor = (titleBar.isHovered ? Theme.barHover : Theme.bar).cgColor
        titleRule.layer?.backgroundColor = Theme.hairline.cgColor
        updateContentLayers()
    }

    /// Subclasses colour their own layers here.
    func updateContentLayers() {}

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Appearing

    /// A new card draws in like a line on a plan: its outline first, then what it holds.
    func playDrawIn() {
        guard Theme.Motion.isAllowed else { return }
        titleBar.alphaValue = 0
        content.alphaValue = 0
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.base
            animator().alphaValue = 1
        } completionHandler: {
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Theme.Motion.base
                    self.titleBar.animator().alphaValue = 1
                    self.content.animator().alphaValue = 1
                }
            }
        }
    }

    // MARK: Gestures

    @objc private func handleClick(_ g: NSClickGestureRecognizer) {
        canvas?.controller?.select(.card(card.id))
        canvas?.takeFocus()
    }

    @objc private func handleDoubleClick(_ g: NSClickGestureRecognizer) {
        canvas?.zoom(toCard: card.id)
    }

    @objc private func handleMove(_ g: NSPanGestureRecognizer) {
        guard let canvas else { return }
        switch g.state {
        case .began:
            dragOrigin = CGPoint(x: card.x, y: card.y)
            canvas.controller?.select(.card(card.id))
            // The card moves under the pointer, which would keep re-asking the title bar for
            // its open hand. Cursor regions are switched off until the drag ends.
            window?.disableCursorRects()
            NSCursor.closedHand.set()
        case .changed:
            let t = g.translation(in: canvas.document)
            canvas.controller?.moveCard(card.id, x: max(CardView.farLeft, dragOrigin.x + t.x), y: max(CardView.farLeft, dragOrigin.y + t.y))
        case .ended, .cancelled, .failed:
            if g.state == .ended {
                let t = g.translation(in: canvas.document)
                canvas.controller?.moveCard(card.id, x: max(CardView.farLeft, dragOrigin.x + t.x), y: max(CardView.farLeft, dragOrigin.y + t.y))
            }
            window?.enableCursorRects()
            window?.invalidateCursorRects(for: titleBar)
        default: break
        }
    }

    @objc private func handleResize(_ g: NSPanGestureRecognizer) {
        guard let canvas else { return }
        switch g.state {
        case .began:
            dragSize = CGSize(width: card.width, height: card.height)
            canvas.controller?.select(.card(card.id))
        case .changed, .ended:
            let t = g.translation(in: canvas.document)
            canvas.controller?.resizeCard(card.id, width: dragSize.width + t.x, height: dragSize.height + t.y)
        default: break
        }
    }

    @objc private func handleLinkDrag(_ g: NSPanGestureRecognizer) {
        guard let canvas, let dot = g.view as? PortDotView else { return }
        let start = CanvasGeometry.outputPoint(of: card, port: dot.port)
        let now = g.location(in: canvas.document)
        switch g.state {
        case .began, .changed:
            canvas.showPendingLink(from: card.id, port: dot.port, start: start, to: now)
        case .ended:
            canvas.clearPendingLink()
            canvas.finishLink(from: card.id, port: dot.port, at: now)
        default:
            canvas.clearPendingLink()
        }
    }
}

/// What a card view needs to know beyond its own card.
struct CardContext {
    var isSelected = false
    var isFocused = false
    /// The card is where the run is right now: an agent at work or waiting on a hand-off.
    var isLive = false
    var linkedInputs = false
    var linkedPorts: Set<String> = []
    var warning: String?
    var inputCount = 0
    var result: String?
    var sessionState: SessionState = .notStarted
    var mark = RunMark()
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The corner you drag to resize a card: three short diagonal strokes.
final class ResizeGripView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.inkSecondary.setStroke()
        let path = NSBezierPath()
        for inset in stride(from: CGFloat(5), through: 11, by: 3) {
            path.move(to: NSPoint(x: bounds.maxX - 3, y: bounds.maxY - inset))
            path.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - 3))
        }
        path.lineWidth = 1
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }
}
