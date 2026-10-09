import AppKit
import QueenBeeCore

/// A round dot on a card's edge that a link starts from or lands on.
final class PortDotView: NSView {
    let port: String
    let isOutput: Bool
    var isLinked = false { didSet { needsDisplay = true } }

    init(port: String, isOutput: Bool) {
        self.port = port
        self.isOutput = isOutput
        let d = CanvasGeometry.portRadius * 2 + 4
        super.init(frame: NSRect(x: 0, y: 0, width: d, height: d))
        toolTip = isOutput ? "Drag to another card to link \(portLabel(port))" : "Input"
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: r)
        (isLinked ? Palette.accent : Palette.card).setFill()
        path.fill()
        (isLinked ? Palette.accent : Palette.link).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

/// A card on the canvas: a title bar to drag it by, dots for its links, a corner to resize it.
/// Its frame is the card's rectangle widened by `gutter` on each side, so the dots that
/// straddle the card's edges stay inside the view and can be clicked.
class CardView: NSView {
    static let gutter: CGFloat = CanvasGeometry.portRadius + 2

    private(set) var card: Card
    weak var canvas: CanvasView?

    let body = FlippedView()
    let titleBar = FlippedView()
    let content = FlippedView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let resizeGrip = ResizeGripView()
    private var inputDot: PortDotView?
    private var outputDots: [PortDotView] = []
    private var dragOrigin = CGPoint.zero
    private var dragSize = CGSize.zero

    override var isFlipped: Bool { true }

    init(card: Card) {
        self.card = card
        super.init(frame: CardView.frame(for: card))
        wantsLayer = true

        body.wantsLayer = true
        body.layer?.cornerRadius = CanvasGeometry.cornerRadius
        body.layer?.masksToBounds = true
        body.layer?.borderWidth = 1
        addSubview(body)

        titleBar.wantsLayer = true
        body.addSubview(titleBar)
        body.addSubview(content)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        titleBar.addSubview(iconView)
        nameLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        titleBar.addSubview(nameLabel)

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
        let target = CardView.frame(for: new)
        if frame != target { frame = target }
        if portsChanged { rebuildPorts() }
        applyCard()

        let selected = context.isSelected
        body.layer?.borderColor = (selected ? Palette.accent : Palette.cardBorder).cgColor
        body.layer?.borderWidth = selected ? 2 : 1
        inputDot?.isLinked = context.linkedInputs
        for dot in outputDots { dot.isLinked = context.linkedPorts.contains(dot.port) }
        needsLayout = true
    }

    private func applyCard() {
        nameLabel.stringValue = card.name
        iconView.image = NSImage(systemSymbolName: CanvasGeometry.icon(for: card.kind), accessibilityDescription: card.kind.label)
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
        content.frame = NSRect(x: 0, y: CanvasGeometry.titleHeight, width: body.bounds.width,
                               height: body.bounds.height - CanvasGeometry.titleHeight)
        iconView.frame = NSRect(x: 12, y: 7, width: 16, height: 16)
        nameLabel.frame = NSRect(x: 34, y: 7, width: max(0, titleBar.bounds.width - 34 - titleTrailingInset), height: 17)

        let origin = CGPoint(x: card.x - g, y: card.y)
        if let dot = inputDot { place(dot, at: CanvasGeometry.inputPoint(of: card), origin: origin) }
        for dot in outputDots { place(dot, at: CanvasGeometry.outputPoint(of: card, port: dot.port), origin: origin) }
        let s = CanvasGeometry.resizeHandle
        resizeGrip.frame = NSRect(x: bounds.width - g - s, y: bounds.height - s, width: s, height: s)
        layoutContent()
    }

    /// Room kept free at the title's right for a subclass's own controls.
    var titleTrailingInset: CGFloat { 12 }

    /// Subclasses lay out what sits under the title.
    func layoutContent() {}

    private func place(_ dot: PortDotView, at point: CGPoint, origin: CGPoint) {
        dot.frame.origin = CGPoint(x: point.x - origin.x - dot.bounds.width / 2, y: point.y - origin.y - dot.bounds.height / 2)
    }

    override func updateLayer() {
        body.layer?.backgroundColor = Palette.card.cgColor
        titleBar.layer?.backgroundColor = Palette.cardTitle.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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
        case .changed, .ended:
            let t = g.translation(in: canvas.document)
            canvas.controller?.moveCard(card.id, x: max(0, dragOrigin.x + t.x), y: max(0, dragOrigin.y + t.y))
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
            canvas.showPendingLink(from: start, to: now)
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
    var linkedInputs = false
    var linkedPorts: Set<String> = []
    var warning: String?
    var inputCount = 0
    var result: String?
    var sessionState: SessionState = .notStarted
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The corner you drag to resize a card: three short diagonal strokes.
final class ResizeGripView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setStroke()
        let path = NSBezierPath()
        for inset in stride(from: CGFloat(5), through: 13, by: 4) {
            path.move(to: NSPoint(x: bounds.maxX - 3, y: bounds.maxY - inset))
            path.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.maxY - 3))
        }
        path.lineWidth = 1.2
        path.stroke()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .bottomRight, directions: .all))
    }
}
