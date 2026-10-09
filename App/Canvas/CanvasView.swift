import AppKit
import Observation
import QueenBeeCore
import SwiftTerm

/// The surface cards sit on: drafting paper with a dot matrix. Flipped so a card's y grows
/// downward, as the flow file stores it.
final class CanvasDocumentView: NSView {
    /// What the add-card palette puts on the pasteboard when a row is dragged. Nothing else
    /// in the app, the terminals included, accepts it, so the drop always lands on the canvas.
    static let cardKindType = NSPasteboard.PasteboardType("dev.queenbee.card-kind")

    weak var canvas: CanvasView?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.paper.setFill()
        dirtyRect.fill()

        // Zoomed out, dots crowd together and shrink below a pixel. Every second or fourth
        // dot is kept, drawn larger, so the matrix looks the same density on screen.
        let zoom = max(canvas?.scrollView.magnification ?? 1, 0.01)
        var step = CanvasGeometry.gridStep
        while step * zoom < 14 { step *= 2 }
        let size = max(1.6, 1.6 / zoom)
        Theme.dot.setFill()
        var y = (dirtyRect.minY / step).rounded(.down) * step
        while y <= dirtyRect.maxY {
            var x = (dirtyRect.minX / step).rounded(.down) * step
            while x <= dirtyRect.maxX {
                NSBezierPath(ovalIn: NSRect(x: x - size / 2, y: y - size / 2, width: size, height: size)).fill()
                x += step
            }
            y += step
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // Delete and forward delete remove the selected card or link.
        if event.keyCode == 51 || event.keyCode == 117 {
            canvas?.controller?.deleteSelection()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Cards dropped from the palette

    private func kind(in info: NSDraggingInfo) -> CardKind? {
        let board = info.draggingPasteboard
        let raw = board.string(forType: Self.cardKindType)
            ?? board.data(forType: Self.cardKindType).flatMap { String(data: $0, encoding: .utf8) }
        return raw.flatMap(CardKind.init(rawValue:))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.types?.contains(Self.cardKindType) == true ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let kind = kind(in: sender) else { return false }
        canvas?.controller?.addCard(kind, at: convert(sender.draggingLocation, from: nil))
        return true
    }
}

/// The zoomable canvas of one flow. An NSScrollView with magnification holds one large
/// document view; cards are its subviews, so a card's terminal is a real view that takes
/// clicks and keys at any zoom.
final class CanvasView: NSView, NSGestureRecognizerDelegate {
    static let documentSize = CGSize(width: 14000, height: 11000)
    /// Room to pan left of and above the canvas's origin. Without it a card at the origin
    /// could never be moved out from under the palette, which floats over that corner.
    static let margin: CGFloat = 3000
    /// The height of the window's title bar, which floats over the canvas's top edge.
    static let titleBarHeight: CGFloat = 52

    let scrollView = NSScrollView()
    let document = CanvasDocumentView()
    private let linkLayer = LinkLayerView()
    private var cardViews: [String: CardView] = [:]
    private(set) weak var controller: FlowController?
    private var scrollMonitor: Any?
    private var responderObservation: NSKeyValueObservation?
    private var didInitialScroll = false
    /// False until the flow's saved cards are on screen, so only cards added later draw in.
    private var didFirstSync = false
    private var boundsObservation: NSObjectProtocol?

    init(controller: FlowController) {
        self.controller = controller
        super.init(frame: .zero)

        document.canvas = self
        document.frame = CGRect(origin: .zero, size: CanvasView.documentSize)
        document.bounds.origin = CGPoint(x: -CanvasView.margin, y: -CanvasView.margin)
        // The link layer covers the whole document and shares its coordinates, so a link is
        // drawn with the same numbers its cards are placed with.
        linkLayer.frame = document.bounds
        linkLayer.bounds.origin = document.bounds.origin
        document.addSubview(linkLayer)

        document.registerForDraggedTypes([CanvasDocumentView.cardKindType])
        scrollView.documentView = document
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.2
        scrollView.maxMagnification = 3
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        scrollView.drawsBackground = false
        // The canvas runs under the window's transparent title bar, so it must not push its
        // content down to make room for one.
        scrollView.automaticallyAdjustsContentInsets = false
        addSubview(scrollView)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleBackgroundClick(_:)))
        click.delegate = self
        document.addGestureRecognizer(click)

        // The zoom pill shows the zoom level, however it was changed: pinch, menu or button.
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObservation = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.publishZoom() }
        }

        observe()
    }

    private func publishZoom() {
        let zoom = Double(scrollView.magnification)
        if let controller, abs(controller.zoom - zoom) > 0.004 {
            controller.zoom = zoom
            document.needsDisplay = true
        }
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
        linkLayer.passes = controller.linkPasses
        linkLayer.liveLinkIDs = controller.liveLinkIDs
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
                if didFirstSync { view.playDrawIn() }
            }
            var context = CardContext()
            context.isSelected = controller.selection == .card(card.id)
            context.isFocused = controller.focusedCardID == card.id
            context.linkedInputs = flow.links.contains { $0.to == card.id }
            context.linkedPorts = Set(flow.links(from: card.id).map(\.port))
            context.warning = warnings[card.id]
            context.inputCount = Set(flow.links(into: card.id).map(\.from)).count
            context.result = controller.results[card.id]
            context.mark = controller.marks[card.id] ?? RunMark()
            if card.kind == .agent, let agentView = view as? AgentCardView {
                let session = controller.session(forCard: card.id)
                context.sessionState = session.state
                context.isLive = session.state == .working || session.state == .needsYou
                    || context.mark.arrivals > context.mark.passes
                agentView.attach(terminal: session.view)
            }
            view.update(card: card, context: context)
        }
        for (id, view) in cardViews where !seen.contains(id) {
            view.removeFromSuperview()
            cardViews[id] = nil
        }
        didFirstSync = true
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
            guard let self, event.window === self.window else { return event }
            return self.panInsteadOfScrolling(event, atWindowPoint: event.locationInWindow) ? nil : event
        }

        responderObservation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
            Task { @MainActor in self?.firstResponderChanged(in: window) }
        }
    }

    override func layout() {
        super.layout()
        if !didInitialScroll, bounds.width > 0 {
            didInitialScroll = true
            // Start with the canvas's origin just clear of the panels floating over its left edge.
            document.scroll(CGPoint(x: -(AppServices.shared.canvasObstruction.left + 20), y: -(CanvasView.titleBarHeight + 16)))
        }
    }

    /// A scroll over a terminal that doesn't have the keyboard pans the canvas. Returns
    /// whether it did; when it didn't, the event goes on to whatever is under it.
    private func panInsteadOfScrolling(_ event: NSEvent, atWindowPoint point: NSPoint) -> Bool {
        guard let terminal = terminal(atWindowPoint: point), !isFocused(terminal) else { return false }
        scrollView.scrollWheel(with: event)
        return true
    }

    private func terminal(atWindowPoint point: NSPoint) -> NSView? {
        guard let content = window?.contentView else { return nil }
        // hitTest takes a point in the superview's coordinates. The content view is flipped, so
        // converting into its own coordinates would look for the terminal at the mirrored spot.
        var view = content.hitTest(content.superview?.convert(point, from: nil) ?? point)
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

    /// A link is being dragged out of a port. The card under the pointer shows whether the
    /// link would be taken there.
    func showPendingLink(from cardID: String, port: String, start: CGPoint, to point: CGPoint) {
        linkLayer.pending = (start, point)
        let target = card(at: point)
        for (id, view) in cardViews {
            if id == target?.id, id != cardID, let flow = controller?.flow {
                view.linkDrop = flow.linkProblem(from: cardID, port: port, to: id) == nil ? .accepts : .refuses
            } else {
                view.linkDrop = .none
            }
        }
    }

    func clearPendingLink() {
        linkLayer.pending = nil
        cardViews.values.forEach { $0.linkDrop = .none }
    }

    private func card(at point: CGPoint) -> Card? {
        controller?.flow.cards.last { CanvasGeometry.frame(of: $0).insetBy(dx: -CardView.gutter, dy: 0).contains(point) }
    }

    func finishLink(from cardID: String, port: String, at point: CGPoint) {
        guard let controller, let target = card(at: point), target.id != cardID else { return }
        controller.link(from: cardID, port: port, to: target.id)
    }

    // MARK: Test support

    func testFocus(cardID: String?) {
        if let cardID, let terminal = controller?.sessions[cardID]?.view {
            window?.makeFirstResponder(terminal)
        } else {
            takeFocus()
        }
    }

    func testSetMagnification(_ value: Double) {
        scrollView.setMagnification(CGFloat(value), centeredAt: inClip(visibleCenter))
        document.needsDisplay = true
    }

    var testViewState: JSONValue {
        let r = scrollView.documentVisibleRect
        return ["magnification": .number(Double(scrollView.magnification)), "x": .number(Double(r.minX)), "y": .number(Double(r.minY)),
                "width": .number(Double(r.width)), "height": .number(Double(r.height))]
    }

    /// Scrolls the wheel over a card's terminal, or over bare canvas. "system" hands a real
    /// event to this process, so it travels the whole road: the event queue, the monitor,
    /// the view under the pointer. "direct" skips the queue and gives the event to the same
    /// decision the monitor makes, for when the system won't deliver to a window that is
    /// behind others.
    func testScroll(cardID: String?, dy: Double, mode: String) -> String? {
        guard let window, let controller else { return nil }
        let target: CGPoint
        if let cardID, let card = controller.flow.card(cardID) {
            target = CGPoint(x: card.x + card.width / 2, y: card.y + card.height / 2)
        } else {
            // A spot on the visible canvas that no card covers.
            let r = scrollView.documentVisibleRect
            let frames = controller.flow.cards.map { CanvasGeometry.frame(of: $0).insetBy(dx: -20, dy: -20) }
            // Away from the corners, where the palette, zoom control and status line float.
            var spot = CGPoint(x: r.midX, y: r.maxY - 90 / max(scrollView.magnification, 0.01))
            var tries = 0
            while tries < 40, frames.contains(where: { $0.contains(spot) }) {
                spot.x -= 40
                tries += 1
            }
            target = spot
        }
        let inWindow = document.convert(target, to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        guard let primary = NSScreen.screens.first,
              let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy), wheel2: 0, wheel3: 0) else { return nil }
        cg.location = CGPoint(x: onScreen.x, y: primary.frame.height - onScreen.y)
        if mode == "system" {
            cg.postToPid(getpid())
            return "system"
        }
        guard let event = NSEvent(cgEvent: cg) else { return nil }
        if !panInsteadOfScrolling(event, atWindowPoint: inWindow) {
            let under = window.contentView.flatMap { $0.hitTest($0.superview?.convert(inWindow, from: nil) ?? inWindow) }
            (under ?? scrollView).scrollWheel(with: event)
        }
        return "direct"
    }

    // MARK: Zoom

    // The scroll view's zoom calls take the clip view's coordinates. Those differ from the
    // canvas's own because the canvas's origin is set in from the document's corner.
    private func inClip(_ point: CGPoint) -> CGPoint { scrollView.contentView.convert(point, from: document) }
    private func inClip(_ rect: CGRect) -> CGRect { scrollView.contentView.convert(rect, from: document) }

    /// The middle of what is on screen, in canvas points: where a new card goes.
    var visibleCenter: CGPoint {
        let r = scrollView.documentVisibleRect
        // The middle of what the floating panels leave uncovered, not of the whole window.
        let covered = AppServices.shared.canvasObstruction
        let zoom = max(scrollView.magnification, 0.01)
        return CGPoint(x: r.midX + (covered.left - covered.right) / 2 / zoom, y: r.midY)
    }

    func zoom(by factor: CGFloat) {
        let target = min(scrollView.maxMagnification, max(scrollView.minMagnification, scrollView.magnification * factor))
        scrollView.setMagnification(target, centeredAt: inClip(visibleCenter))
        document.needsDisplay = true
    }

    func zoomToActualSize() {
        scrollView.setMagnification(1, centeredAt: inClip(visibleCenter))
        document.needsDisplay = true
    }

    func zoomToFit() {
        guard let cards = controller?.flow.cards, !cards.isEmpty else { return }
        let box = cards.map(CanvasGeometry.frame(of:)).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -40, dy: -40)
        fit(box)
    }

    /// Zooms so `box` fills the part of the canvas the floating panels leave uncovered.
    /// The panels are a fixed size on screen, so their size in canvas points depends on the
    /// zoom being solved for: fit once to find it, then again with the room they need.
    private func fit(_ box: CGRect) {
        let covered = AppServices.shared.canvasObstruction
        var wanted = box
        for _ in 0..<3 {
            scrollView.magnify(toFit: inClip(wanted))
            let zoom = max(scrollView.magnification, 0.01)
            // The see-through title bar and its buttons sit over the canvas's top; the status
            // line and zoom control over its foot.
            wanted = CGRect(x: box.minX - covered.left / zoom, y: box.minY - CanvasView.titleBarHeight / zoom,
                            width: box.width + (covered.left + covered.right) / zoom,
                            height: box.height + (CanvasView.titleBarHeight + 50) / zoom)
        }
        scrollView.magnify(toFit: inClip(wanted))
        document.needsDisplay = true
    }

    func zoom(toCard id: String) {
        guard let card = controller?.flow.card(id) else { return }
        fit(CanvasGeometry.frame(of: card).insetBy(dx: -40, dy: -40))
    }
}
