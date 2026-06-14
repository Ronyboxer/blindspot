//
//  Formatters.swift
//  Blind Spot
//
//  Small, shared formatting helpers so telemetry reads consistently everywhere.
//  Units are imperial (miles, mph) — Blind Spot is US-first.
//

import Foundation

enum Format {

    private static let metersPerMile = 1609.344
    private static let mphPerMPS = 2.2369362921   // (m/s) → mph

    /// Meters → miles string, 1 decimal place. e.g. 2540 -> "1.6".
    static func miles(_ meters: Double) -> String {
        String(format: "%.1f", meters / metersPerMile)
    }

    /// meters/second → mph, whole number. Negative (invalid GPS speed) -> "0".
    static func mph(_ metersPerSecond: Double) -> String {
        String(format: "%.0f", max(0, metersPerSecond) * mphPerMPS)
    }

    /// Seconds → "M:SS" or "H:MM:SS". e.g. 642 -> "10:42".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// A short, friendly date for ride rows / recaps. e.g. "Jun 11, 2:30 PM".
    static func rideDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }

    /// A coordinate pair, monospace-friendly. e.g. "37.3382, -121.8863".
    static func coord(lat: Double, lng: Double) -> String {
        String(format: "%.4f, %.4f", lat, lng)
    }
}
