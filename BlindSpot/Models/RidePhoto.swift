//
//  RidePhoto.swift
//  Blind Spot
//
//  A photo captured during a ride (Supabase `photos` table — manual flags — and,
//  best-effort, `automated_photos` — machine captures). The Pi owns capture +
//  upload to public storage; the iPhone only READS the `storage_url` to display.
//

import Foundation

struct RidePhoto: Identifiable, Hashable {
    let id: UUID
    let rideId: UUID
    let url: URL
    let capturedAt: Date?
    let eventType: String?
    /// True for `automated_photos` (machine), false for manual `photos`.
    let isMachine: Bool
}
