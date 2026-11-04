import QueenBeeDesign
import SwiftUI
import UIKit

/// The iPad and iPhone app's names for the design system in `QueenBeeDesign`, which the Mac app shares, so a
/// flow looks the same on the device as it does on the Mac. Colours come from there and nowhere else.
///
/// Colour carries meaning and nothing else. Ink is structure. Orange is live. Green is "the run passed
/// through". Red is "it stopped here". Cobalt is selected or focused.
nonisolated enum Theme {
    // MARK: Colour, as light and dark pairs
    // The app's long-standing names for the roles in `Palette`, the same as the Mac's. New code can take `Palette` directly.

    /// Behind a screen's content, and the canvas.
    static let paper = Palette.panel.platform
    /// A panel, a sheet, a list.
    static let surface = Palette.overlay.platform
    /// A strip or a row set off from what it sits on: a header, a field, a card.
    static let bar = Palette.raised.platform
    /// Under a finger, where the Mac has the pointer over it.
    static let barHover = Palette.hover.platform
    static let ink = Palette.text.platform
    static let inkSecondary = Palette.textMuted.platform
    static let hairline = Palette.hairline.platform
    /// A line that has to be seen: around a control or a card.
    static let outline = Palette.hairlineStrong.platform
    /// The canvas's dot matrix.
    static let dot = Palette.canvasDot.platform

    static let live = Palette.live.platform
    static let liveTint = Palette.liveTint.platform
    static let liveInk = Palette.liveText.platform
    static let passTint = Palette.passTint.platform
    static let passInk = Palette.passText.platform
    static let failTint = Palette.failTint.platform
    static let failInk = Palette.failText.platform
    static let select = Palette.accent.platform

    static let terminal = Palette.terminal.platform
    static let terminalInk = Palette.terminalText.platform

    // MARK: Type

    /// Monospace, for anything that names or counts: card titles, ports, badges, flow names.
    /// A fixed size, for the canvas, which is zoomed rather than read at the system's text size.
    static func mono(_ size: CGFloat = Size.terminal, _ weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Sans, for anything read as a sentence on the canvas.
    static func sans(_ size: CGFloat = Size.label, _ weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size, weight: weight)
    }

    /// The sizes of the Mac's canvas and of its terminals, which is what the canvas here is drawn in so a card
    /// matches the Mac's. They are the Mac's type roles at the Mac's size (never the larger touch size), so the two
    /// can't drift. A card's name is semibold and the words on a card are medium, as on the Mac.
    enum Size {
        /// A card's name in its title bar: `TextRole.headline`, 13 semibold.
        static let cardName: CGFloat = TextRole.headline.desk
        /// A word on a card: a state, a port, a summary. `TextRole.captionLabel`, 11.5 medium.
        static let label: CGFloat = TextRole.captionLabel.desk
        /// A figure on a card, and the run badge on its title bar: `TextRole.figure`, 11 medium.
        static let figure: CGFloat = TextRole.figure.desk
        /// A terminal's type: `TextRole.mono`, 12.
        static let terminal: CGFloat = TextRole.mono.desk
    }

    /// A card's name, in the Mac's weight.
    static func cardName(_ size: CGFloat = Size.cardName) -> UIFont { sans(size, .semibold) }
    /// A word on a card, in the Mac's weight.
    static func cardLabel(_ size: CGFloat = Size.label, _ weight: UIFont.Weight = .medium) -> UIFont { sans(size, weight) }

    /// Outside the canvas, a list held in the hand and tapped with a finger takes its type from the roles
    /// (`.textRole(.body)` and the rest), which are larger than the Mac's and grow with the person's text size.
    enum Touch {
        /// The least height of anything a finger is meant to hit.
        static let target: CGFloat = DS.Size.touchTarget
    }

    // MARK: Shape

    enum Space {
        static let xs: CGFloat = DS.Space.xs
        static let s: CGFloat = DS.Space.s
        static let m: CGFloat = DS.Space.m
        static let l: CGFloat = DS.Space.l
        static let xl: CGFloat = DS.Space.xl
    }

    enum Radius {
        static let card: CGFloat = DS.Radius.m
        static let badge: CGFloat = DS.Radius.xs
    }

    enum Stroke {
        static let card: CGFloat = DS.Stroke.hairline
        static let link: CGFloat = DS.Stroke.link
        static let selected: CGFloat = DS.Stroke.focus
    }

    /// The paper's dot matrix: one dot at every step, as on the Mac's canvas.
    enum Grid {
        static let step: CGFloat = 24
        static let dot: CGFloat = 1.6
    }

    // MARK: Motion

    enum Motion {
        static let quickDuration = DS.Motion.quickDuration
        static let standardDuration = DS.Motion.standardDuration
        static let travelDuration = DS.Motion.travelDuration
        static let march = DS.Motion.march

        /// False when the person has asked the device for less motion.
        @MainActor static var isAllowed: Bool { !UIAccessibility.isReduceMotionEnabled }

        /// For `withAnimation`, which can't take `.dsAnimation`: the design system's curves, or none, so the
        /// change happens at once, when the person has asked for less motion. Views animate a value with `.dsAnimation(_:value:)`.
        @MainActor static var quick: Animation? { DS.Motion.resolved(DS.Motion.quick, reduceMotion: !isAllowed) }
        @MainActor static var standard: Animation? { DS.Motion.resolved(DS.Motion.standard, reduceMotion: !isAllowed) }
    }
}

extension UIColor {
    /// The same colour for SwiftUI views.
    nonisolated var ui: Color { Color(uiColor: self) }
}
