//
//  Color+BlindSpot.swift
//  Blind Spot
//
//  The brand color palette + a convenient hex initializer.
//
//  Design rules baked in here:
//   - Yellow/black, dark-mode-first, "hi-vis safety product" vibe.
//   - Yellow tokens are CHROME (buttons, accents). Black/charcoal/graphite are
//     surfaces. Warm off-white is ink on dark.
//   - The "SEMANTIC" colors (severe / moderate / good) are ONLY for data
//     visualization — i.e. hazard severity. Never use them as UI chrome.
//   - Severity is never color-only: always pair with an SF Symbol + text label
//     (safety-critical + colorblind-safe). See HazardBadge.
//

import SwiftUI

extension Color {

    /// Create a `Color` from a 24-bit RGB hex value, e.g. `Color(hex: 0xFFD60A)`.
    ///
    /// We accept an `Int` (not a string) so the color tokens below read cleanly
    /// and are checked at compile time.
    init(hex: UInt32, opacity: Double = 1.0) {
        let red   = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8)  & 0xFF) / 255.0
        let blue  = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    // MARK: - Brand chrome

    /// Primary brand color (coral). Use for primary buttons, key accents.
    static let bsPrimary       = Color(hex: 0xEE5634)
    /// Max-attention highlight (e.g. the crash-SOS countdown). Use sparingly.
    static let bsPrimaryBright  = Color(hex: 0xFF6B4A)
    /// Pressed state for primary controls.
    static let bsPrimaryDeep    = Color(hex: 0xC8431F)

    // MARK: - Surfaces & ink

    /// Primary surface + ink (near-black).
    static let bsBlack    = Color(hex: 0x0A0A0A)
    /// Elevated surfaces / navigation chrome.
    static let bsCharcoal = Color(hex: 0x1A1A1A)
    /// Cards.
    static let bsGraphite = Color(hex: 0x242424)
    /// Warm off-white — primary text on dark surfaces.
    static let bsWhite    = Color(hex: 0xFAFAF7)

    // MARK: - Semantic (DATA VIZ ONLY — hazard severity)
    // Do NOT use these as UI chrome. They exist so hazards read consistently
    // and are always paired with an icon + label elsewhere.

    /// Severe hazard.
    static let bsSevere   = Color(hex: 0xE5484D)
    /// Moderate hazard.
    static let bsModerate = Color(hex: 0xFF8A00)
    /// Good / safe / low severity.
    static let bsGood     = Color(hex: 0x30A46C)
}
