import AppKit
import SwiftUI

/// The Flight plan design system. The canvas reads as an engineering drawing: drafting
/// paper, ink lines, and one signal colour for whatever is live. Every view takes its
/// colours, type, spacing and timing from here, so the look changes in one place.
///
/// Colour carries meaning and nothing else. Ink is structure. Orange is live. Green is
/// "the run passed through". Red is "it stopped here". Cobalt is selected or focused.
enum Theme {
    // MARK: Colour, as light and dark pairs

    static let paper = pair(0xE3EAF1, 0x0F1B2B)
    static let surface = pair(0xFFFFFF, 0x16263A)
    static let bar = pair(0xF3F6FA, 0x1B2E46)
    static let barHover = pair(0xE7EDF4, 0x223955)
    static let ink = pair(0x1F3A5F, 0xCFE0F5)
    static let inkSecondary = pair(0x5A7190, 0x8AA3C2)
    static let hairline = pair(0x1F3A5F, 0xCFE0F5, alpha: 0.22, 0.2)
    static let grid = pair(0x1F3A5F, 0xCFE0F5, alpha: 0.07, 0.055)
    static let gridMajor = pair(0x1F3A5F, 0xCFE0F5, alpha: 0.14, 0.11)

    static let live = pair(0xFF6B2C, 0xFF8A4C)
    static let liveTint = pair(0xFFE4D6, 0x4A2413)
    static let liveInk = pair(0x8A3410, 0xFFC7A8)
    static let passTint = pair(0xDDF3E4, 0x143524)
    static let passInk = pair(0x17603A, 0x7FD6A0)
    static let failTint = pair(0xFBE3E3, 0x4A1B1B)
    static let failInk = pair(0xA32D2D, 0xF09595)
    static let select = pair(0x2F6FED, 0x6EA0FF)

    static let terminal = pair(0x10243D, 0x0A1420)
    static let terminalInk = pair(0xCFE0F5, 0xCFE0F5)

    private static func pair(_ light: Int, _ dark: Int, alpha lightAlpha: CGFloat = 1, _ darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { $0.isDark ? rgb(dark, darkAlpha) : rgb(light, lightAlpha) }
    }

    private static func rgb(_ hex: Int, _ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    // MARK: Type

    /// Monospace, for anything that names or counts: card titles, ports, badges, the log.
    static func mono(_ size: CGFloat = Size.body, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Sans, for anything read as a sentence: settings, help text, instructions.
    static func sans(_ size: CGFloat = Size.body, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    enum Size {
        static let caption: CGFloat = 11
        static let body: CGFloat = 12
        static let title: CGFloat = 13
        static let heading: CGFloat = 15
    }

    // MARK: Shape

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let card: CGFloat = 3
        static let badge: CGFloat = 2
    }

    enum Stroke {
        static let card: CGFloat = 1
        static let link: CGFloat = 1.5
        static let selected: CGFloat = 2
    }

    // MARK: Motion

    enum Motion {
        /// Hover, press, anything tied to the pointer.
        static let fast: TimeInterval = 0.12
        /// Selecting, panels opening, a count ticking up.
        static let base: TimeInterval = 0.2
        /// A new card drawing in.
        static let slow: TimeInterval = 0.4
        /// One step of the dashes marching along a live link.
        static let march: TimeInterval = 0.8

        /// False when the person has asked the Mac for less motion.
        static var isAllowed: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    }

    // MARK: Appearance

    /// System, light or dark, as chosen in the View menu and Settings.
    enum Mode: String, CaseIterable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: "Match the system"
            case .light: "Light"
            case .dark: "Dark"
            }
        }
    }

    static let modeKey = "appearance"

    static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .system
    }

    static func apply(_ mode: Mode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension NSColor {
    /// The same colour for SwiftUI views.
    var ui: Color { Color(nsColor: self) }

    /// The colour as it looks in `appearance`, for layers, which don't follow light and dark by themselves.
    func cg(in appearance: NSAppearance) -> CGColor {
        var resolved = cgColor
        appearance.performAsCurrentDrawingAppearance { resolved = self.cgColor }
        return resolved
    }

    /// The colour fixed to how it looks in `appearance`, for views that take a plain colour once.
    func fixed(in appearance: NSAppearance) -> NSColor {
        NSColor(cgColor: cg(in: appearance)) ?? self
    }
}

extension Font {
    static func dsMono(_ size: CGFloat = Theme.Size.body, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func dsSans(_ size: CGFloat = Theme.Size.body, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// The look shared by the controls that float over the canvas: the palette, the settings
/// panel, the zoom pill, the status strip. Drawn like a card, lifted by one soft shadow.
struct FloatingPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.ink.ui, lineWidth: Theme.Stroke.card))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
    }
}

extension View {
    func floatingPanel() -> some View { modifier(FloatingPanel()) }
}

/// A small tinted label: a state, a count, a check.
struct Badge: View {
    enum Tone { case plain, live, pass, fail }
    let text: String
    var symbol: String?
    var tone: Tone = .plain

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            if !text.isEmpty { Text(text) }
        }
        .font(.dsMono(Theme.Size.caption, .medium))
        .foregroundStyle(foreground.ui)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(background.ui, in: RoundedRectangle(cornerRadius: Theme.Radius.badge))
    }

    private var foreground: NSColor {
        switch tone {
        case .plain: Theme.inkSecondary
        case .live: Theme.liveInk
        case .pass: Theme.passInk
        case .fail: Theme.failInk
        }
    }

    private var background: NSColor {
        switch tone {
        case .plain: Theme.bar
        case .live: Theme.liveTint
        case .pass: Theme.passTint
        case .fail: Theme.failTint
        }
    }
}
