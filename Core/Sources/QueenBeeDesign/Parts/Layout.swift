import SwiftUI

/// Something raised on the panel: a card, a group of properties, a menu.
public struct RaisedSurface: ViewModifier {
    var radius: CGFloat
    var ground: Shade

    public init(radius: CGFloat = DS.Radius.l, ground: Shade = Palette.raised) {
        self.radius = radius
        self.ground = ground
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(ground.color, in: shape)
            .overlay(shape.strokeBorder(Palette.hairlineStrong.color, lineWidth: DS.Stroke.hairline))
    }
}

extension View {
    /// Marks a block that is waiting on the person: the surface it is on, with a thin rule in the live colour down
    /// its leading edge, rather than a live fill. The words in it are in the live text colour.
    public func liveRule() -> some View {
        overlay(alignment: .leading) {
            Rectangle().fill(Palette.live.color).frame(width: DS.Stroke.focus).accessibilityHidden(true)
        }
    }

    public func raisedSurface(radius: CGFloat = DS.Radius.l, ground: Shade = Palette.raised) -> some View {
        modifier(RaisedSurface(radius: radius, ground: ground))
    }

    /// Fades out what scrolls under an edge where there is more out of view: clear for `DS.Size.lineFadeClear` at
    /// the very edge, for a control to stand on, then fading in over the rest of `DS.Size.lineFade`.
    public func edgeFade(leading: Bool, trailing: Bool) -> some View {
        mask {
            let clear = DS.Size.lineFadeClear / DS.Size.lineFade
            // A mask only reads how see-through it is, so these two say "hidden" and "shown", not colours.
            let hidden = Color.clear, shown = Color.black
            HStack(spacing: 0) {
                LinearGradient(stops: [.init(color: hidden, location: 0), .init(color: hidden, location: clear),
                                       .init(color: shown, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: leading ? DS.Size.lineFade : 0)
                Rectangle().fill(shown)
                LinearGradient(stops: [.init(color: shown, location: 0), .init(color: hidden, location: 1 - clear),
                                       .init(color: hidden, location: 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: trailing ? DS.Size.lineFade : 0)
            }
        }
    }
}

/// A one-point line between rows or sections.
public struct DSDivider: View {
    var isVertical: Bool

    public init(vertical: Bool = false) { isVertical = vertical }

    public var body: some View {
        Rectangle()
            .fill(Palette.hairline.color)
            .frame(width: isVertical ? DS.Stroke.hairline : nil, height: isVertical ? nil : DS.Stroke.hairline)
            .accessibilityHidden(true)
    }
}

/// The small heading over a group: "Pinned", a project's name, "Properties". Something may sit at its end, like a + button.
public struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    public init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    @Environment(\.density) private var density

    public var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text(title).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.s)
            trailing
        }
        .textRole(.sectionHeader)
        .foregroundStyle(Palette.textFaint.color)
        .padding(.horizontal, DS.Space.s)
        .frame(minHeight: density == .desk ? 26 : 32)
    }
}

extension SectionHeader where Trailing == EmptyView {
    public init(_ title: String) { self.init(title) { EmptyView() } }
}

/// A keyboard shortcut, as it is shown beside a menu item or a button: ⌘K.
public struct KeyHint: View {
    let keys: [String]

    public init(_ keys: String...) { self.keys = keys }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .textRole(.monoCaption)
                    .foregroundStyle(Palette.textMuted.color)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Palette.hover.color, in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
