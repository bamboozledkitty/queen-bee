import SwiftUI

// Measures that only a touch screen needs: rows tall enough for a finger, the columns that keep a line of
// text readable on an iPad. They sit beside the Mac's in `DS` so both apps draw from one list.

extension DS.Space {
    /// Above and below a message that stands alone on a page: "Looking for your Mac".
    public static let placeholder: CGFloat = 60
}

extension DS.Radius {
    /// A menu that floats over a phone's tab bar.
    public static let panel: CGFloat = 24
}

extension DS.Size {
    /// A short row, a chip or a field: under the finger's 44, with room around it that is tappable too.
    public static let rowCompact: CGFloat = 36
    /// A row that stands alone on a page: a Mac to pair with.
    public static let rowTall: CGFloat = 52
    /// A floating chip: the branch a flow works on.
    public static let chip: CGFloat = 32
    /// A badge on a touch screen.
    public static let badgeTouch: CGFloat = 24
    /// A flow's tile in a list.
    public static let flowTile: CGFloat = 40
    /// A status dot on a touch screen.
    public static let dotTouch: CGFloat = 9
    /// The dot in the connection strip.
    public static let dot: CGFloat = 8

    /// Columns for a row's leading symbol, so the text after it lines up, from the narrowest to the widest.
    public static let iconSlotWide: CGFloat = 18
    public static let iconSlotRow: CGFloat = 22
    public static let iconSlotLarge: CGFloat = 24

    /// The tab bar's buttons, and the one that opens its menu.
    public static let tabWidth: CGFloat = 64
    public static let tabMenuWidth: CGFloat = 56
    public static let tabHeight: CGFloat = 46
    /// The number between a stepper's buttons, on a touch screen.
    public static let stepValueTouch: CGFloat = 34

    /// How far each level of a list of nested flows is set in.
    public static let treeIndent: CGFloat = 14
    /// The room left under a list for the floating bar over it.
    public static let floatingBarClearance: CGFloat = 96
    /// The thin bar that shows a share of the whole.
    public static let meter: CGFloat = 2

    /// The widest a line of floating text, a banner or a menu is let grow, from the narrowest.
    public static let menuNarrowWidth: CGFloat = 280
    public static let noteWidth: CGFloat = 300
    public static let calloutWidth: CGFloat = 360
    public static let bannerWidth: CGFloat = 380
    public static let messageWidth: CGFloat = 420
    public static let plateWidth: CGFloat = 440
    public static let sheetWidth: CGFloat = 560

    /// A box for a message being rewritten: its taller and its shorter form.
    public static let textAreaTall: CGFloat = 160
    public static let textArea: CGFloat = 120
}
