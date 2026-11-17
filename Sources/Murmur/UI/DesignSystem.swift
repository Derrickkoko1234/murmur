import SwiftUI

/// The design system for Murmur.
///
/// Direction: a quiet, modern Mac app in the vein of Wispr Flow. A sidebar sits on the
/// window background, and the selected page is one large rounded card inset beside it.
/// Neutral greys carry everything; a serif display face gives headlines and stats some
/// warmth. Every value a view needs lives here; components never declare their own colors,
/// sizes, radii or durations.
///
/// The rules that keep it calm:
/// - Red means recording. Nothing else in the app is red.
/// - No gradients and no glow. Depth comes from a lighter surface and a hairline border.
/// - One emphasis color: ink. Primary buttons are ink-filled, not tinted.
enum DS {

    // MARK: - Color

    enum Color {
        // Surfaces, from the window inward.
        /// The window and sidebar.
        static let background = adaptive(light: 0xF3F2EF, dark: 0x181818)
        /// The page card beside the sidebar.
        static let surface = adaptive(light: 0xFFFFFF, dark: 0x202020)
        /// Cards and grouped lists sitting on the page.
        static let raised = adaptive(light: 0xF7F6F3, dark: 0x262626)
        /// A hovered row or sidebar item.
        static let hover = adaptive(light: 0xEDEBE7, dark: 0x2A2A2A)
        /// The selected sidebar item.
        static let selection = adaptive(light: 0xE6E4DF, dark: 0x303030)
        /// Hairline borders and row dividers.
        static let border = adaptive(light: 0xE4E1DB, dark: 0x303030)

        // Text
        static let ink = adaptive(light: 0x1A1A1A, dark: 0xEDEDED)
        /// Supporting text: subtitles, labels.
        static let inkSecondary = adaptive(light: 0x6B6862, dark: 0x9C9C9C)
        /// Timestamps, section dates, placeholder-level detail.
        static let inkTertiary = adaptive(light: 0x9C9890, dark: 0x6F6F6F)
        /// Text and icons on an ink-filled control.
        static let inkInverse = adaptive(light: 0xFFFFFF, dark: 0x111111)

        /// The hero card. Dark in both appearances, so it reads as the one focal point.
        static let hero = swatch(0x111111)
        static let heroInk = swatch(0xF5F5F5)
        static let heroInkSecondary = swatch(0xA8A8A8)
        /// The button on the hero card.
        static let heroControl = swatch(0x2E2E2E)

        /// The recording indicator. The only red in the app.
        static let record = swatch(0xE5484D)
        /// Dictionary warnings and applied corrections.
        static let caution = adaptive(light: 0xB7791F, dark: 0xE0A44A)

        // The HUD pill. Dark in both appearances, like the hero.
        static let hud = swatch(0x111111)
        static let hudInk = swatch(0xF5F5F5)
        static let hudBorder = SwiftUI.Color.white.opacity(0.1)

        private static func swatch(_ hex: UInt32) -> SwiftUI.Color { SwiftUI.Color(hex: hex) }

        /// Resolves to the light or dark value for the current appearance.
        private static func adaptive(light: UInt32, dark: UInt32) -> SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
    }

    // MARK: - Type

    /// The system face for UI; New York (the system serif) for headlines and stats.
    enum Font {
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium)
        static let label = SwiftUI.Font.system(size: 12)
        static let body = SwiftUI.Font.system(size: 14)
        static let bodyEmphasis = SwiftUI.Font.system(size: 14, weight: .medium)
        static let sidebar = SwiftUI.Font.system(size: 14, weight: .medium)
        static let logo = SwiftUI.Font.system(size: 20, weight: .bold)
        /// A group's heading within a page.
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)
        static let title = SwiftUI.Font.system(size: 26, weight: .semibold)
        /// The hero card's headline.
        static let display = SwiftUI.Font.system(size: 28, design: .serif)
        /// Big stat figures.
        static let stat = SwiftUI.Font.system(size: 30, design: .serif)
        /// The label beside a stat figure.
        static let statLabel = SwiftUI.Font.system(size: 15)
        /// Timers. Monospaced digits so they don't jitter as they tick.
        static let counter = SwiftUI.Font.system(size: 13, weight: .medium).monospacedDigit()
        /// Letter spacing for small uppercase section labels, in points.
        static let sectionTracking: CGFloat = 1.2
    }

    // MARK: - Spacing

    /// A 4pt grid.
    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let roomy: CGFloat = 16
        static let wide: CGFloat = 24
        static let panel: CGFloat = 32
        static let page: CGFloat = 48
    }

    // MARK: - Size

    enum Size {
        static let sidebarWidth: CGFloat = 220
        static let statsWidth: CGFloat = 260
        /// The timestamp column beside each transcription.
        static let timeColumn: CGFloat = 84
        /// Readable line length for transcriptions.
        static let textColumn: CGFloat = 640
        static let icon: CGFloat = 15
        static let smallIcon: CGFloat = 11
        static let recordDot: CGFloat = 8

        static let windowMinWidth: CGFloat = 860
        static let windowMinHeight: CGFloat = 580
        static let settingsWidth: CGFloat = 520
        static let settingsHeight: CGFloat = 560
        static let editorWidth: CGFloat = 440

        static let hudWidth: CGFloat = 320
        static let hudHeight: CGFloat = 52
        static let hudWaveformWidth: CGFloat = 64
        static let hudWaveformHeight: CGFloat = 22
    }

    // MARK: - Radius

    enum Radius {
        static let chip: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 16
        /// The page card.
        static let page: CGFloat = 20
    }

    // MARK: - Border

    enum Border {
        static let hairline: CGFloat = 1
    }

    // MARK: - Elevation

    enum Shadow {
        /// The HUD pill against whatever's behind it.
        static let hud = Spec(color: .black.opacity(0.3), radius: 16, x: 0, y: 6)

        struct Spec {
            let color: SwiftUI.Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }

    // MARK: - Motion

    enum Motion {
        /// Hover and selection changes.
        static let quick = Animation.easeOut(duration: 0.12)
        /// Page and list changes.
        static let page = Animation.easeInOut(duration: 0.18)
        /// The HUD fading in and out.
        static let hudFade: TimeInterval = 0.16
        /// How long "Copied" shows before reverting.
        static let copiedFeedback: Duration = .seconds(1.4)
    }
}

// MARK: - Hex helpers

private extension SwiftUI.Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
