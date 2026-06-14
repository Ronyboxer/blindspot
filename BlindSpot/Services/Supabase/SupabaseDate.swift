//
//  SupabaseDate.swift
//  Blind Spot
//
//  Date <-> ISO-8601 string conversion for Supabase/Postgres `timestamptz`.
//
//  We convert dates to strings ourselves rather than relying on the JSON
//  encoder's default Date handling (which serializes Date as a raw number that
//  Postgres rejects). Decoding is lenient about the number of fractional-second
//  digits Postgres returns (it varies, e.g. ".02709" or ".123456").
//

import Foundation

enum SupabaseDate {

    /// Date → ISO-8601 string Postgres accepts, e.g. "2026-06-13T22:00:00Z".
    static func string(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// ISO-8601 string (with any fractional precision + offset) → Date.
    static func date(from string: String) -> Date? {
        // Strip the fractional seconds so any digit count parses, then parse.
        let cleaned = string.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression
        )
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: cleaned)
    }
}
