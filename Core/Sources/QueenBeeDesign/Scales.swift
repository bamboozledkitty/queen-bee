import SwiftUI

/// How tightly a screen is packed. The Mac is read at a desk with a pointer, so rows are short and type is small.
/// The iPhone and iPad are held and tapped, so everything a finger hits is at least 44 points and type is larger.
public enum Density: Sendable {
    case desk, touch

    /// What this device is, unless a view says otherwise.
    public static var platform: Density {
        #if os(macOS)
        .desk
        #else
        .touch
        #endif
    }
}

extension EnvironmentValues {
    @Entry public var density: Density = .platform
}

/// The measures every screen is laid out with. A view takes a number from here or from a part that does.
public enum DS {
    /// Gaps and padding, on a 4-point step.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        /// Between an icon and its label, and inside a small row.
        public static let tight: CGFloat = 6
        public static let s: CGFloat = 8
        /// Padding inside a row that is a little roomier than `s`.
        public static let snug: CGFloat = 10
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        /// Around a first-run screen's content.
        public static let page: CGFloat = 40
        public static let xxxl: CGFloat = 48
    }

    /// Corner radii. Small things get small corners; nothing is fully round except pills and dots.
    public enum Radius {
        /// A key hint, a badge.
        public static let xs: CGFloat = 4
        /// A button, a sidebar row, a menu item.
        public static let s: CGFloat = 6
        /// A field, a terminal inside a card, a menu.
        public static let m: CGFloat = 8
        /// A card, the inset panel.
        public static let l: CGFloat = 10
        /// A popover, the command menu, a floating bar.
        public static let xl: CGFloat = 12
        /// A sheet on the iPhone.
        public static let sheet: CGFloat = 28
    }

    /// Line widths.
    public enum Stroke {
        public static let hairline: CGFloat = 1
        public static let link: CGFloat = 1.5
        /// The ring around a selected card or a focused field.
        public static let focus: CGFloat = 2
        /// The track of the progress ring and of a run's line of stops.
        public static let track: CGFloat = 3
    }

    /// Heights and widths that keep the layout in line from screen to screen.
    public enum Size {
        /// The least height of anything a finger is meant to hit.
        public static let touchTarget: CGFloat = 44
        /// A row in the Mac's sidebar.
        public static let navRow: CGFloat = 28
        /// A row in a list on the Mac.
        public static let listRow: CGFloat = 40
        /// A list's group header on the Mac.
        public static let groupHeader: CGFloat = 36
        /// The widest a place's list or page is drawn on the Mac, centred, so a name and its time stay close.
        public static let placeColumn: CGFloat = 880
        /// The log of a run, opened beside the list of runs on the Mac.
        public static let placePeek: CGFloat = 380
        /// The widest the few lines a place says when it is empty are set.
        public static let emptyText: CGFloat = 380
        /// A run's number, and when it started, at the two ends of its row, in columns so they line up.
        public static let runNumberColumn: CGFloat = 40
        public static let runTimeColumn: CGFloat = 84
        /// The sheet that sets two runs side by side on the Mac: room for a card's name and a column for each run.
        public static let compareSheet: CGFloat = 720
        /// The column of a card's name in it.
        public static let compareName: CGFloat = 180
        /// A small rounded tag with a flow's name in it.
        public static let tag: CGFloat = 22
        /// How tall a sheet of settings is on the Mac: the shortest it is let get, what it opens at, and the tallest.
        public static let sheetMinHeight: CGFloat = 360
        public static let sheetHeight: CGFloat = 620
        public static let sheetMaxHeight: CGFloat = 760
        /// The header across the top of the inset panel.
        public static let header: CGFloat = 44
        /// The row of pill tabs under it.
        public static let tabRow: CGFloat = 40
        /// A button on the Mac.
        public static let control: CGFloat = 28
        /// The Mac's sidebar.
        public static let sidebarWidth: CGFloat = 236
        /// The column a row's leading symbol sits in, so the text after it lines up.
        public static let iconSlot: CGFloat = 16
        /// A small button that holds one symbol: close, refresh.
        public static let iconButton: CGFloat = 16
        /// A row of tabs or a bar inside a panel.
        public static let bar: CGFloat = 30
        /// How far down from the top the find panel, the command menu and the orchestrator's callout float.
        public static let findInset: CGFloat = 90
        public static let commandInset: CGFloat = 140
        public static let calloutInset: CGFloat = 230
        /// Floating panels' widths: settings, find, a menu, a popover, the command menu, the first-run window.
        public static let settingsWidth: CGFloat = 460
        public static let findWidth: CGFloat = 440
        public static let menuWidth: CGFloat = 320
        public static let popoverWidth: CGFloat = 250
        public static let commandWidth: CGFloat = 640
        public static let onboardingWidth: CGFloat = 520
        /// Room left at the top left for the window's close, minimise and zoom buttons.
        public static let windowControlsInset: CGFloat = 64
        /// The command menu's search field, a row, and its footer.
        public static let commandField: CGFloat = 52
        public static let commandRow: CGFloat = 38
        /// The progress pill's ring, a stop on a run's line, and one of a For each's item ticks.
        public static let progressRing: CGFloat = 18
        public static let stop: CGFloat = 16
        public static let itemTick: CGFloat = 6
        /// The room each stop on a run's line takes, and the widest the line's panel is drawn.
        public static let stopColumn: CGFloat = 104
        public static let progressLineWidth: CGFloat = 720
        /// How far in a run's line fades at an edge where more stops are out of view, and how much of that, at the
        /// very edge, is cleared for the arrow and its count.
        public static let lineFade: CGFloat = 100
        public static let lineFadeClear: CGFloat = 50
        public static let commandFooter: CGFloat = 36
        /// A small label's least height: a badge.
        public static let badge: CGFloat = 20
        /// The number between a stepper's buttons, and each button.
        public static let stepValue: CGFloat = 22
        public static let stepButton: CGFloat = 18
    }

    /// Timing, the same on every device.
    public enum Motion {
        /// Hover, press, anything tied to the pointer or a finger.
        public static let quickDuration: TimeInterval = 0.15
        /// Selecting, panels opening, a panel changing height.
        public static let standardDuration: TimeInterval = 0.25
        /// The canvas moving: zoom, fit, going to a card.
        public static let travelDuration: TimeInterval = 0.3
        /// One step of the dashes marching along a live link.
        public static let march: TimeInterval = 0.8

        /// Springs with no bounce, so a change that is interrupted carries on from where it was.
        public static let quick: Animation = .snappy(duration: quickDuration, extraBounce: 0)
        public static let standard: Animation = .snappy(duration: standardDuration, extraBounce: 0)
        /// The animation to run: `animation` as it is, or none when the person has asked for less motion, so the
        /// change happens at once. A softened curve would still move what moves, which is what they asked not to see.
        public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    /// Roughly how far a floating menu, a popover or the command menu lifts off what is behind it. Depth comes
    /// from the surface ladder and hairlines; a floating menu is the one place a shadow is allowed.
    public enum Lift {
        public static let radius: CGFloat = 12
        public static let offset: CGFloat = 4
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(DS.Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// Animates a change in `value` with one of the design system's curves, or at once with nothing moving when
    /// the person has asked for Reduce Motion. Use this, not `.animation(_:value:)`, so the setting is honoured.
    public func dsAnimation<Value: Equatable>(_ animation: Animation = DS.Motion.quick, value: Value) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

extension View {
    /// The shadow of a floating menu: the command menu, and nothing else. Everything else is lifted by its surface
    /// and a hairline.
    public func dsLift() -> some View {
        shadow(color: Palette.lift.color, radius: DS.Lift.radius, y: DS.Lift.offset)
    }
}
