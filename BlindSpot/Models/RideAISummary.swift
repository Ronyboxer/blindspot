//
//  RideAISummary.swift
//  Blind Spot
//
//  The Raspberry Pi's post-ride AI analysis, stored in the Supabase `ai_summary`
//  table and linked to a ride by `ride_id` (= rides.id). The iPhone only READS
//  this — the Pi owns writing it. Provides the automated rating + summary shown
//  on the ride recap.
//

import Foundation

struct RideAISummary: Identifiable, Hashable {
    let id: UUID
    let rideId: UUID
    let summary: String
    /// 0–100 accessibility score from the AI.
    let accessibilityScore: Int
    /// Word rating, e.g. "poor" / "fair" / "good" / "excellent".
    let accessibilityRating: String
    let potholesDetected: Bool
    let potholeCount: Int
    let labels: [String]
    let observations: [String]
    let roadHazards: [String]
    let recommendedMapTags: [String]

    /// Road hazards minus the "none_detected" sentinel.
    var realHazards: [String] {
        roadHazards.filter { $0.lowercased() != "none_detected" && !$0.isEmpty }
    }
}
