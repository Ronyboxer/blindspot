//
//  Font+BlindSpot.swift
//  Blind Spot
//
//  Typography. The brand uses two bundled custom faces:
//
//   - INSTRUMENT SERIF (Regular) — display / titles / headlines. An elegant,
//     editorial serif used large. It ships in a single weight by design.
//   - JETBRAINS MONO — all numbers / telemetry (speed, distance, timers, coords)
//     AND the small uppercase micro-labels + button text. Gives the instrument
//     feel and keeps numeric columns aligned.
//
//   - Body text stays SF Pro (system) — Instrument Serif is a display face and
//     isn't meant for long runs of small text.
//
//  The font files live in Resources/Fonts and are registered via UIAppFonts in
//  the generated Info.plist (see project.yml). `BSFont` holds the PostScript
//  names; everything else references the `Font` tokens below, so call sites
//  never change when we tweak sizes/weights.
//
//  `relativeTo:` lets these custom fonts scale with Dynamic Type.
//

import SwiftUI

/// PostScript names of the bundled fonts (verified from the .ttf name tables).
enum BSFont {
    static let serif         = "InstrumentSerif-Regular"
    static let monoRegular   = "JetBrainsMono-Regular"
    static let monoMedium    = "JetBrainsMono-Medium"
    static let monoSemiBold  = "JetBrainsMono-SemiBold"
    static let monoBold      = "JetBrainsMono-Bold"
    static let monoExtraBold = "JetBrainsMono-ExtraBold"
}

extension Font {

    // MARK: - Display & titles (Instrument Serif)

    /// Big editorial hero text (e.g. onboarding question, ready-to-ride).
    static let bsDisplay  = Font.custom(BSFont.serif, size: 48, relativeTo: .largeTitle)
    /// Screen / section titles.
    static let bsTitle    = Font.custom(BSFont.serif, size: 34, relativeTo: .title)
    /// Sub-titles / card headers / ride-row dates.
    static let bsHeadline = Font.custom(BSFont.serif, size: 24, relativeTo: .title3)

    // MARK: - Body (SF Pro — readability)

    static let bsBody = Font.system(size: 17, weight: .regular, design: .default)

    // MARK: - Micro-labels & buttons (JetBrains Mono)

    /// Small uppercase labels (e.g. under a StatTile, legend headers).
    static let bsCaption = Font.custom(BSFont.monoMedium, size: 12, relativeTo: .caption)
    /// Button / call-to-action text (rendered uppercase by the buttons).
    static let bsButton  = Font.custom(BSFont.monoBold, size: 17, relativeTo: .headline)

    // MARK: - Telemetry numbers (JetBrains Mono)

    /// Large monospaced number — primary readout on a StatTile / live telemetry.
    static let bsStatLarge  = Font.custom(BSFont.monoExtraBold, size: 40, relativeTo: .largeTitle)
    /// Medium monospaced number (e.g. ride-row stats).
    static let bsStatMedium = Font.custom(BSFont.monoBold, size: 22, relativeTo: .title2)
    /// Small monospaced number (e.g. coordinates, inline values).
    static let bsStatSmall  = Font.custom(BSFont.monoSemiBold, size: 15, relativeTo: .subheadline)
}
