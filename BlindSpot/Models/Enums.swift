//
//  Enums.swift
//  Blind Spot
//
//  The shared domain enums. Each has a `String` raw value so it maps cleanly to
//  a database column later, plus UI helpers (`displayName`, `symbolName`, and a
//  brand color for severity) so views render hazards/events consistently.
//
//  All `Codable` so models serialize cleanly when the real data layer arrives.
//

import SwiftUI

// MARK: - HazardType

/// The kind of road hazard. Used by both `Hazard` and (optionally) `RideEvent`.
enum HazardType: String, Codable, CaseIterable, Identifiable {
    case pothole
    case debris
    case glass
    case water
    case blockedLane
    case construction

    var id: String { rawValue }

    /// Human-facing label.
    var displayName: String {
        switch self {
        case .pothole:     return "Pothole"
        case .debris:      return "Debris"
        case .glass:       return "Glass"
        case .water:       return "Water"
        case .blockedLane: return "Blocked Lane"
        case .construction: return "Construction"
        }
    }

    /// SF Symbol used to render this hazard on the map / in badges.
    var symbolName: String {
        switch self {
        case .pothole:      return "circle.bottomhalf.filled"
        case .debris:       return "leaf.fill"
        case .glass:        return "shippingbox.fill"
        case .water:        return "drop.fill"
        case .blockedLane:  return "xmark.octagon.fill"
        case .construction: return "cone.fill"
        }
    }

    /// Distinct color per hazard type so the map pins are differentiable.
    var color: Color {
        switch self {
        case .pothole:      return .bsPrimary            // coral
        case .debris:       return Color(hex: 0xE6BC00)  // amber
        case .glass:        return Color(hex: 0x2BB3C0)  // teal
        case .water:        return Color(hex: 0x3B82F6)  // blue
        case .blockedLane:  return .bsSevere             // red
        case .construction: return .bsModerate           // orange
        }
    }
}

// MARK: - Severity

/// How dangerous a hazard is. Carries a brand color for DATA VIZ ONLY.
/// Severity is never shown by color alone — always paired with icon + label.
enum Severity: String, Codable, CaseIterable, Identifiable {
    case minor
    case moderate
    case severe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minor:    return "Minor"
        case .moderate: return "Moderate"
        case .severe:   return "Severe"
        }
    }

    /// SF Symbol conveying the severity level (redundant with color for
    /// colorblind-safety).
    var symbolName: String {
        switch self {
        case .minor:    return "exclamationmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .severe:   return "exclamationmark.octagon.fill"
        }
    }

    /// Brand semantic color. ONLY for hazard data viz — never UI chrome.
    var color: Color {
        switch self {
        case .minor:    return .bsGood
        case .moderate: return .bsModerate
        case .severe:   return .bsSevere
        }
    }
}

// MARK: - HazardStatus

/// Lifecycle of a crowd-sourced hazard report.
enum HazardStatus: String, Codable, CaseIterable, Identifiable {
    case reported
    case confirmed
    case expired

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reported:  return "Reported"
        case .confirmed: return "Confirmed"
        case .expired:   return "Expired"
        }
    }

    var symbolName: String {
        switch self {
        case .reported:  return "flag.fill"
        case .confirmed: return "checkmark.seal.fill"
        case .expired:   return "clock.badge.xmark.fill"
        }
    }
}

// MARK: - EventType

/// A notable moment during a ride. `crash` triggers the SOS flow; the others are
/// hazard flags / detected anomalies. `detected` on `RideEvent` indicates whether
/// the (future) ML service auto-detected it vs. a manual flag.
enum EventType: String, Codable, CaseIterable, Identifiable {
    case manualFlag
    case impact
    case hardBrake
    case swerve
    case crash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manualFlag: return "Manual Flag"
        case .impact:     return "Impact"
        case .hardBrake:  return "Hard Brake"
        case .swerve:     return "Swerve"
        case .crash:      return "Crash"
        }
    }

    var symbolName: String {
        switch self {
        case .manualFlag: return "flag.fill"
        case .impact:     return "burst.fill"
        case .hardBrake:  return "hand.raised.fill"
        case .swerve:     return "arrow.triangle.swap"
        case .crash:      return "sos"
        }
    }
}

// MARK: - BikingSkill

/// The rider's self-assessed cycling ability. Collected during onboarding and
/// shown on the profile.
enum BikingSkill: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced
    case pro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        case .pro:          return "Pro"
        }
    }

    /// A short supporting line for the onboarding option rows.
    var blurb: String {
        switch self {
        case .beginner:     return "New to riding or just getting comfortable"
        case .intermediate: return "Confident on familiar routes"
        case .advanced:     return "Comfortable in traffic and on long rides"
        case .pro:          return "Race, commute daily, or ride competitively"
        }
    }

    var symbolName: String {
        switch self {
        case .beginner:     return "figure.walk"
        case .intermediate: return "bicycle"
        case .advanced:     return "figure.outdoor.cycle"
        case .pro:          return "trophy.fill"
        }
    }
}

// MARK: - RideFrequency

/// How often the rider bikes in a typical week. Collected during onboarding.
enum RideFrequency: String, Codable, CaseIterable, Identifiable {
    case rarely        // < 1 / week
    case occasional    // 1–2 / week
    case regular       // 3–4 / week
    case daily         // 5+ / week

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rarely:     return "Rarely"
        case .occasional: return "1–2 / week"
        case .regular:    return "3–4 / week"
        case .daily:      return "5+ / week"
        }
    }

    var symbolName: String {
        switch self {
        case .rarely:     return "calendar"
        case .occasional: return "calendar.badge.clock"
        case .regular:    return "calendar.badge.checkmark"
        case .daily:      return "flame.fill"
        }
    }
}
