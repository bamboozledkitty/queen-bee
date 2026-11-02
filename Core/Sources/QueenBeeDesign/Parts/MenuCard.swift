import SwiftUI

/// One action in a `menuCard`.
public struct MenuCardItem: Identifiable {
    public let title: String
    public let isEnabled: Bool
    public let action: () -> Void

    public var id: String { title }

    public init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }
}

/// Which row of a `menuCard` the arrow keys land on.
public enum MenuCardNavigation {
    /// The usable row `step` rows on from `current`, staying put at either end. With no current row, the first
    /// usable one going down and the last going up.
    public static func move(from current: Int?, by step: Int, enabled: [Bool]) -> Int? {
        let usable = enabled.indices.filter { enabled[$0] }
        guard let current, let position = usable.firstIndex(of: current) else {
            return step > 0 ? usable.first : usable.last
        }
        return usable[min(max(position + step, 0), usable.count - 1)]
    }
}

/// What a button that opens a `menuCard` says: an optional icon, its name, and the small arrow that shows it
/// opens something.
public struct MenuCardLabel: View {
    let title: String
    let systemImage: String?

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: DS.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(Palette.textMuted.color)
            }
            Text(title)
            MenuCardArrow()
        }
        .fixedSize()
    }
}

/// The small arrow on anything that opens a card.
public struct MenuCardArrow: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Palette.textFaint.color)
    }
}

extension View {
    /// Opens a small card of actions under this view, the same kind of card as the branch form and branch lists.
    /// A thin line separates the sections. Arrow keys move, Return picks, Escape closes.
    public func menuCard(isPresented: Binding<Bool>, sections: [[MenuCardItem]]) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            MenuCardList(sections: sections.filter { !$0.isEmpty }) { isPresented.wrappedValue = false }
                .presentationBackground(Palette.overlay.color)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct MenuCardList: View {
    let sections: [[MenuCardItem]]
    let onClose: () -> Void

    @Environment(\.density) private var density
    @State private var highlighted: Int?
    @FocusState private var isFocused: Bool

    private var items: [MenuCardItem] { sections.flatMap { $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sections.indices, id: \.self) { section in
                if section > 0 {
                    DSDivider().padding(.vertical, DS.Space.xs)
                }
                let start = sections[..<section].reduce(0) { $0 + $1.count }
                ForEach(Array(sections[section].enumerated()), id: \.element.id) { offset, item in
                    row(item, at: start + offset)
                }
            }
        }
        .padding(DS.Space.xs)
        .fixedSize()
        .background(Palette.overlay.color)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            if let highlighted { pick(items[highlighted]) }
            return .handled
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onAppear { isFocused = true }
    }

    private func row(_ item: MenuCardItem, at index: Int) -> some View {
        Button { pick(item) } label: {
            Text(item.title)
                .textRole(.body)
                .foregroundStyle((item.isEnabled ? Palette.text : Palette.textFaint).color)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.s)
                .frame(minHeight: density == .desk ? DS.Size.navRow : DS.Size.touchTarget)
                .background(highlighted == index && item.isEnabled ? Palette.hover.color : .clear,
                            in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isEnabled)
        .onHover { inside in
            if inside && item.isEnabled { highlighted = index }
        }
    }

    private func move(_ step: Int) {
        highlighted = MenuCardNavigation.move(from: highlighted, by: step, enabled: items.map(\.isEnabled))
    }

    /// Closes the card first, so a question the action asks isn't left underneath it.
    private func pick(_ item: MenuCardItem) {
        guard item.isEnabled else { return }
        onClose()
        Task { @MainActor in item.action() }
    }
}
