import AppKit
import QueenBeeCore

/// A logic card: a line saying what it is set to, a label for each named output,
/// and a warning when its wiring would leave a run stuck.
final class LogicCardView: CardView {
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let warningLabel = NSTextField(labelWithString: "")
    private var portLabels: [NSTextField] = []

    override init(card: Card) {
        super.init(card: card)
        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.maximumNumberOfLines = 0
        summaryLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(summaryLabel)
        warningLabel.font = .systemFont(ofSize: 11, weight: .medium)
        warningLabel.textColor = Palette.warning
        warningLabel.lineBreakMode = .byTruncatingTail
        content.addSubview(warningLabel)
    }

    override func update(card new: Card, context: CardContext) {
        super.update(card: new, context: context)
        summaryLabel.stringValue = context.result ?? CardSummary.text(for: new, inputs: context.inputCount)
        summaryLabel.textColor = context.result == nil ? .secondaryLabelColor : .labelColor
        warningLabel.stringValue = context.warning.map { "⚠ \($0)" } ?? ""
        warningLabel.isHidden = context.warning == nil

        let named = ports(of: new).count > 1 ? ports(of: new) : []
        if portLabels.map(\.stringValue) != named.map(portLabel) {
            portLabels.forEach { $0.removeFromSuperview() }
            portLabels = named.map { port in
                let label = NSTextField(labelWithString: portLabel(port))
                label.font = .systemFont(ofSize: 11.5, weight: .medium)
                label.alignment = .right
                label.lineBreakMode = .byTruncatingTail
                content.addSubview(label)
                return label
            }
        }
        needsLayout = true
    }

    override func layoutContent() {
        let w = content.bounds.width
        let foot = CGFloat(portLabels.count) * CanvasGeometry.portRowHeight
        let warningHeight: CGFloat = warningLabel.isHidden ? 0 : 16
        let summaryHeight = max(0, content.bounds.height - foot - warningHeight - 12)
        summaryLabel.frame = NSRect(x: 12, y: 6, width: w - 24, height: summaryHeight)
        warningLabel.frame = NSRect(x: 12, y: 6 + summaryHeight, width: w - 24, height: 16)
        for (i, label) in portLabels.enumerated() {
            let rowTop = content.bounds.height - foot + CGFloat(i) * CanvasGeometry.portRowHeight
            label.frame = NSRect(x: 12, y: rowTop + 4, width: w - 12 - 16, height: 16)
        }
    }
}

/// One line about what a logic card is set to.
enum CardSummary {
    static func text(for card: Card, inputs: Int) -> String {
        switch card.kind {
        case .agent: return ""
        case .start:
            let first = (card.command ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return first.isEmpty ? "Write the command" : first
        case .ifElse: return check(card)
        case .switchCard: return "Claude picks one of \((card.branches ?? []).count) branches"
        case .and: return "Waits for all \(inputs) inputs"
        case .or: return "Passes on the first of \(inputs)"
        case .prompt:
            let first = (card.template ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return first.isEmpty ? "Passes the message on" : first
        case .loop: return "\(check(card)) · up to \(card.maxTries ?? 3) tries"
        case .end:
            let file = card.saveTo ?? ""
            return file.isEmpty ? "The final answer shows here" : "Saves to \(file)"
        case .note: return card.text ?? ""
        }
    }

    private static func check(_ card: Card) -> String {
        let value = (card.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "Set its condition" }
        switch card.check ?? .judge {
        case .judge: return "\(value)?"
        case .contains: return "Has \"\(value)\""
        case .notContains: return "No \"\(value)\""
        case .regex: return "Matches /\(value)/"
        }
    }
}
