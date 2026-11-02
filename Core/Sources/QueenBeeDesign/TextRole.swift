import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// What a piece of text is for, which decides its size, weight and letter spacing. Sans for everything read;
/// monospace only for what is copied or compared character by character: ids, paths, branches, costs, code.
///
/// Larger text is drawn slightly tighter, as Linear's is. On touch devices text also grows with the
/// person's text size.
public struct TextRole: Sendable, Hashable {
    public let desk: CGFloat
    public let touch: CGFloat
    public let weight: Font.Weight
    /// Letter spacing in points at the desk size; scaled with the size on touch.
    public let tracking: CGFloat
    public let isMono: Bool

    public init(desk: CGFloat, touch: CGFloat, weight: Font.Weight = .regular, tracking: CGFloat = 0, isMono: Bool = false) {
        self.desk = desk
        self.touch = touch
        self.weight = weight
        self.tracking = tracking
        self.isMono = isMono
    }

    /// How much larger than at the default text size (Large) the person's text size makes sentences: the body style's
    /// sizes, so the same on an iPad as on an iPhone. It is read from the size itself and not from `@ScaledMetric`,
    /// which left the iPad's text at its default size.
    public static func growth(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 14.0 / 17
        case .small: 15.0 / 17
        case .medium: 16.0 / 17
        case .large: 1
        case .xLarge: 19.0 / 17
        case .xxLarge: 21.0 / 17
        case .xxxLarge: 23.0 / 17
        case .accessibility1: 28.0 / 17
        case .accessibility2: 33.0 / 17
        case .accessibility3: 40.0 / 17
        case .accessibility4: 47.0 / 17
        case .accessibility5: 53.0 / 17
        @unknown default: 1
        }
    }

    public func size(_ density: Density) -> CGFloat { density == .desk ? desk : touch }

    public func tracking(_ density: Density) -> CGFloat { density == .desk ? tracking : tracking * touch / desk }

    /// The font at a fixed size, for drawing that is zoomed rather than read at the person's text size: the canvas.
    public func font(_ density: Density = .platform) -> Font {
        .system(size: size(density), weight: weight, design: isMono ? .monospaced : .default)
    }

    #if canImport(AppKit)
    /// The same type for AppKit drawing. `scale` grows it with the canvas's zoom; `digits` makes figures line up.
    public func nsFont(scale: CGFloat = 1, digits: Bool = false) -> NSFont {
        let size = desk * scale
        let w: NSFont.Weight = switch weight {
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        default: .regular
        }
        if isMono { return .monospacedSystemFont(ofSize: size, weight: w) }
        return digits ? .monospacedDigitSystemFont(ofSize: size, weight: w) : .systemFont(ofSize: size, weight: w)
    }
    #endif

    #if canImport(UIKit)
    /// The same type for UIKit drawing, at the desk size: the canvas on a device is drawn in the Mac's sizes, so a
    /// card there matches the Mac's. `scale` grows it with the canvas's zoom; `digits` makes figures line up.
    public func uiFont(scale: CGFloat = 1, digits: Bool = false) -> UIFont {
        let size = desk * scale
        let w: UIFont.Weight = switch weight {
        case .light: .light
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        default: .regular
        }
        if isMono { return .monospacedSystemFont(ofSize: size, weight: w) }
        return digits ? .monospacedDigitSystemFont(ofSize: size, weight: w) : .systemFont(ofSize: size, weight: w)
    }
    #endif

    /// The screen's title: "Needs you", a flow's name in its header on the phone.
    public static let largeTitle = TextRole(desk: 22, touch: 30, weight: .bold, tracking: -0.5)
    /// A panel's or a sheet's title: the selected card's name in the inspector.
    public static let title = TextRole(desk: 17, touch: 22, weight: .semibold, tracking: -0.3)
    /// A name in a row or a card's title bar.
    public static let headline = TextRole(desk: 13, touch: 16, weight: .semibold)
    /// A sentence.
    public static let body = TextRole(desk: 13, touch: 15)
    /// A control's text: buttons, tabs, sidebar rows, menu items.
    public static let label = TextRole(desk: 13, touch: 15, weight: .medium)
    /// Small print: a time, a hint under a field.
    public static let caption = TextRole(desk: 11.5, touch: 13)
    /// A first-run screen's name, above its first sentence.
    public static let display = TextRole(desk: 24, touch: 28, weight: .medium)
    /// A short heading on a touch screen: an empty state's title, a settings page's title.
    public static let heading = TextRole(desk: 14, touch: 17, weight: .medium)
    /// A word on a card or in a pill that has to stand out from the small print around it: a state, a name.
    public static let captionLabel = TextRole(desk: 11.5, touch: 13, weight: .medium)
    /// The title of a sheet or a first-run step, between a headline and a panel's title.
    public static let subtitle = TextRole(desk: 16, touch: 19, weight: .medium, tracking: -0.2)
    /// Fine print under a row: a count, a hint beside a control.
    public static let footnote = TextRole(desk: 11, touch: 12)
    public static let footnoteLabel = TextRole(desk: 11, touch: 12, weight: .medium)
    /// The smallest print: the labels inside a drawn preview, which are never the only place something is said.
    public static let micro = TextRole(desk: 10, touch: 11, weight: .medium)
    /// The small heading over a group: "Pinned", a project's name, "Properties".
    public static let sectionHeader = TextRole(desk: 12, touch: 13, weight: .medium)
    /// Ids, paths, branches, costs.
    public static let mono = TextRole(desk: 12, touch: 14, isMono: true)
    /// A figure drawn on a card: a cost, a count. Digits are all the same width.
    public static let figure = TextRole(desk: 11, touch: 12, weight: .medium)
    public static let monoCaption = TextRole(desk: 11, touch: 12, isMono: true)
    /// A mono name or figure that has to stand out: a port, a count in a stepper.
    public static let monoLabel = TextRole(desk: 12, touch: 14, weight: .medium, isMono: true)
    /// A mono figure that is the point of its row: a run's cost.
    public static let monoHeading = TextRole(desk: 14, touch: 17, weight: .medium, isMono: true)
}

private struct TextRoleModifier: ViewModifier {
    let role: TextRole
    @Environment(\.density) private var density
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        // Names and figures grow half as fast as sentences: they sit in rows and pills, where twice the size no longer fits.
        let scale = TextRole.growth(for: typeSize)
        let grow = density == .touch ? (role.isMono ? 1 + (scale - 1) / 2 : scale) : 1
        content
            .font(.system(size: role.size(density) * grow, weight: role.weight, design: role.isMono ? .monospaced : .default))
            .tracking(role.tracking(density))
    }
}

extension View {
    /// Sets the font for what this text is for, at the size for this device.
    public func textRole(_ role: TextRole) -> some View {
        modifier(TextRoleModifier(role: role))
    }
}

extension DS {
    /// The size of a symbol drawn beside text. Symbols are drawn at a fixed size, not the person's text size, so a
    /// row stays the height it was laid out for.
    public enum IconSize {
        /// A disclosure chevron.
        public static let xxs: CGFloat = 8
        /// A close mark, a small arrow.
        public static let xs: CGFloat = 9
        public static let s: CGFloat = 10
        /// A search glass, a card's kind.
        public static let m: CGFloat = 11
        /// A row's leading symbol.
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 13
        /// A symbol beside a touch row's text, and a small button's.
        public static let xxl: CGFloat = 14
        public static let row: CGFloat = 15
        /// A symbol in a bar's button.
        public static let bar: CGFloat = 16
        /// A tab's symbol.
        public static let tab: CGFloat = 18
        /// An empty state's symbol.
        public static let hero: CGFloat = 28
        /// An empty state's symbol on a touch screen.
        public static let empty: CGFloat = 32
        /// The first screen's symbol.
        public static let display: CGFloat = 40
    }
}

extension View {
    /// Sets a symbol's size from `DS.IconSize`.
    public func dsIcon(_ size: CGFloat, _ weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight))
    }
}
