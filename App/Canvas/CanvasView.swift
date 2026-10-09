import AppKit
import Observation
import QueenBeeCore
import SwiftTerm

/// The surface cards sit on. Flipped so a card's y grows downward, as the flow file stores it.
final class CanvasDocumentView: NSView {
    weak var canvas: CanvasView?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Palette.canvas.setFill()
        dirtyRect.fill()
        // A dot grid for a sense of place; skipped when zoomed far out, where it turns to noise.
        guard (canvas?.scrollView.magnification ?? 1) >= 0.45 else { return }
        Palette.gridDot.setFill()
        let step: CGFloat = 24
        var y = (dirtyRect.minY / step).rounded(.down) * step
        while y <= dirtyRect.maxY {
            var x = (dirtyRect.minX / step).rounded(.down) * step
            while x <= dirtyRect.maxX {
                NSRect(x: x - 1, y: y - 1, width: 2, height: 2).fill()
                x += step
            }
            y += step
        }
    }

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete remove the selected card or link.
        if event.keyCode == 51 || event.keyCode == 117 {
            canvas?.controller?.deleteSelection()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The zoomable canvas of one flow. An NSScrollView with magnification holds one large
/// document view; cards are its subviews, so a card's terminal is a real view that takes
/// clicks and keys at any zoom.
final class CanvasView: NSView, NSGestureRecognizerDelegate {
    static let documentSize = CGSize(width: 12000, height: 9000)

    let scrollView = NSScrollView()
    let document = CanvasDocumentView()
    private let linkLayer = LinkLayerView()
    private var cardViews: [String: CardView] = [:]
    private(set) weak var controller: FlowController?
    private var scrollMonitor: Any?
    private var responderObservation: NSKeyValueObservation?
    private var didInitialScroll = false

    init(controller: FlowController) {
        self.controller = controller
        super.init(frame: .zero)

        document.canvas = self
        document.frame = CGRect(origin: .zero, size: CanvasView.documentSize)
        linkLayer.frame = document.bounds
        linkLayer.autoresizingMask = [.width, .height]
        document.addSubview(linkLayer)

        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.2
        scrollView.maxMagnification = 3
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleBackgroundClick(_:)))
        click.delegate = self
        document.addGestureRecognizer(click)

        observe()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // MARK: Model to views

    /// Re-syncs whenever anything `sync` read changes, then watches again.
    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync() {
        guard let controller else { return }
        let flow = controller.flow
        let warnings = controller.warnings
        linkLayer.flow = flow
        if case .link(let id) = controller.selection { linkLayer.selectedLinkID = id } else { linkLayer.selectedLinkID = nil }

        var seen = Set<String>()
        for card in flow.cards {
            seen.insert(card.id)
            let view: CardView
            if let existing = cardViews[card.id], type(of: existing) == viewClass(for: card) {
                view = existing
            } else {
                cardViews[card.id]?.removeFromSuperview()
                view = card.kind == .agent ? AgentCardView(card: card) : LogicCardView(card: card)
                view.canvas = self
                document.addSubview(view)
                cardViews[card.id] = view
            }
            var context = CardContext()
            context.isSelected = controller.selection == .card(card.id)
            context.isFocused = controller.focusedCardID == card.id
            context.linkedInputs = flow.links.contains { $0.to == card.id }
            context.linkedPorts = Set(flow.links(from: card.id).map(\.port))
            context.warning = warnings[card.id]
            context.inputCount = Set(flow.links(into: card.id).map(\.from)).count
            context.result = controller.results[card.id]
            if card.kind == .agent, let agentView = view as? AgentCardView {
                let session = controller.session(forCard: card.id)
                context.sessionState = session.state
                agentView.attach(terminal: session.view)
            }
            view.update(card: card, context: context)
        }
        for (id, view) in cardViews where !seen.contains(id) {
            view.removeFromSuperview()
            cardViews[id] = nil
        }
    }

    private func viewClass(for card: Card) -> CardView.Type {
        card.kind == .agent ? AgentCardView.self : LogicCardView.self
    }

    // MARK: Window hooks

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        responderObservation = nil
        guard let window else { return }
        if LaunchArguments.floats {
            window.level = .floating
            window.orderFrontRegardless()
        }

        // Scrolling over a terminal you haven't clicked into pans the canvas. Only a focused
        // terminal scrolls its own history.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window, let terminal = self.terminal(under: event),
                  !self.isFocused(terminal) else { return event }
            self.scrollView.scrollWheel(with: event)
            return nil
        }

        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            Task { @MainActor in self?.firstResponderChanged(in: window) }
        }
    }

    override func layout() {
        super.layout()
        if !didInitialScroll, bounds.width > 0 {
            didInitialScroll = true
            document.scroll(.zero)
        }
    }

    private func terminal(under event: NSEvent) -> NSView? {
        guard let content = window?.contentView else { return nil }
        var view = content.hitTest(content.convert(event.locationInWindow, from: nil))
        while let v = view {
            if v is TerminalView { return v }
            view = v.superview
        }
        return nil
    }

    private func isFocused(_ terminal: NSView) -> Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === terminal || responder.isDescendant(of: terminal)
    }

    private func firstResponderChanged(in window: NSWindow) {
        guard let controller else { return }
        var focused: String?
        if let responder = window.firstResponder as? NSView {
            for (id, view) in cardViews where responder.isDescendant(of: view) && !(responder is CardView) {
                focused = id
            }
        }
        if controller.focusedCardID != focused { controller.focusedCardID = focused }
        if let focused, controller.selection != .card(focused) { controller.select(.card(focused)) }
    }

    /// Takes the keyboard away from whichever terminal has it.
    func takeFocus() {
        window?.makeFirstResponder(document)
    }

    // MARK: Background clicks

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        // Only clicks on the bare canvas: a click on a card belongs to the card.
        guard let host = document.superview else { return false }
        return document.hitTest(host.convert(event.locationInWindow, from: nil)) === document
    }

    @objc private func handleBackgroundClick(_ g: NSClickGestureRecognizer) {
        takeFocus()
        if let id = linkLayer.linkID(at: g.location(in: document)) {
            controller?.select(.link(id))
        } else {
            controller?.select(.none)
        }
    }

    // MARK: Linking

    func showPendingLink(from: CGPoint, to: CGPoint) { linkLayer.pending = (from, to) }
    func clearPendingLink() { linkLayer.pending = nil }

    func finishLink(from cardID: String, port: String, at point: CGPoint) {
        guard let controller else { return }
        let target = controller.flow.cards.last { CanvasGeometry.frame(of: $0).insetBy(dx: -CardView.gutter, dy: 0).contains(point) }
        guard let target else { return }
        controller.link(from: cardID, port: port, to: target.id)
    }

    // MARK: Zoom

    /// The middle of what is on screen, in canvas points: where a new card goes.
    var visibleCenter: CGPoint {
        let r = scrollView.documentVisibleRect
        return CGPoint(x: r.midX, y: r.midY)
    }

    func zoom(by factor: CGFloat) {
        let target = min(scrollView.maxMagnification, max(scrollView.minMagnification, scrollView.magnification * factor))
        scrollView.setMagnification(target, centeredAt: visibleCenter)
        document.needsDisplay = true
    }

    func zoomToActualSize() {
        scrollView.setMagnification(1, centeredAt: visibleCenter)
        document.needsDisplay = true
    }

    func zoomToFit() {
        guard let cards = controller?.flow.cards, !cards.isEmpty else { return }
        let box = cards.map(CanvasGeometry.frame(of:)).reduce(CGRect.null) { $0.union($1) }
        scrollView.magnify(toFit: box.insetBy(dx: -60, dy: -60))
        document.needsDisplay = true
    }

    func zoom(toCard id: String) {
        guard let card = controller?.flow.card(id) else { return }
        scrollView.magnify(toFit: CanvasGeometry.frame(of: card).insetBy(dx: -40, dy: -40))
        document.needsDisplay = true
    }
}
