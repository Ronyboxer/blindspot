//
//  RideRepository.swift
//  Blind Spot
//
//  The abstraction between the UI and ride storage. Same idea as
//  `HazardRepository`: mock now, real backend later, no UI changes.
//

import Foundation

protocol RideRepository {
    /// Ride summaries for the Rides list (newest first is the convention).
    func fetchRides() async throws -> [Ride]

    /// Full detail for one ride: the summary plus its polyline points and events.
    /// Returns `nil` if no ride matches `id`.
    func fetchRide(id: UUID) async throws -> (Ride, [RidePoint], [RideEvent])?

    /// Persist a freshly recorded ride (Record screen calls this on STOP).
    func saveRide(_ ride: Ride, points: [RidePoint], events: [RideEvent]) async throws

    /// Update a ride's 1–5 star rating (Recap screen calls this).
    func setRating(rideId: UUID, rating: Int) async throws

    /// Star/unstar a ride.
    func setFavorite(rideId: UUID, favorite: Bool) async throws

    /// Permanently delete a ride (and its points/events).
    func deleteRide(id: UUID) async throws

    /// The Pi's AI analysis for a ride (from `ai_summary`), or nil if none yet.
    func fetchAISummary(rideId: UUID) async throws -> RideAISummary?

    /// Photos captured during a ride (manual `photos` + machine `automated_photos`).
    func fetchPhotos(rideId: UUID) async throws -> [RidePhoto]
}
