//
//  MockRideRepository.swift
//  Blind Spot
//
//  In-memory ride store for the foundation milestone. Seeded from SampleData,
//  supports save + rating mutation so the Record and Recap flows feel real.
//  Conforms to `RideRepository` — drop-in seam for the future backend.
//

import Foundation

final class MockRideRepository: RideRepository {

    /// Detail bundles keyed by ride id, plus an ordering list. We keep the full
    /// detail in memory so `fetchRide` can return points + events.
    private var bundles: [SampleData.RideBundle]

    init() {
        // Newest first (the list convention). SampleData makes them in
        // most-recent-first order already, but sort to be explicit.
        self.bundles = SampleData.makeRides()
            .sorted { $0.ride.startedAt > $1.ride.startedAt }
    }

    func fetchRides() async throws -> [Ride] {
        bundles
            .map(\.ride)
            .sorted { $0.startedAt > $1.startedAt }
    }

    func fetchRide(id: UUID) async throws -> (Ride, [RidePoint], [RideEvent])? {
        guard let bundle = bundles.first(where: { $0.ride.id == id }) else {
            return nil
        }
        return (bundle.ride, bundle.points, bundle.events)
    }

    func saveRide(_ ride: Ride, points: [RidePoint], events: [RideEvent]) async throws {
        // Append the new ride to the in-memory store (newest rides will sort to
        // the top on the next fetch).
        let bundle = SampleData.RideBundle(ride: ride, points: points, events: events)
        bundles.append(bundle)
    }

    func setRating(rideId: UUID, rating: Int) async throws {
        // Find and mutate the stored ride summary in place.
        guard let index = bundles.firstIndex(where: { $0.ride.id == rideId }) else {
            return
        }
        // Clamp to the valid 1...5 range defensively.
        bundles[index].ride.rating = min(5, max(1, rating))
    }

    func setFavorite(rideId: UUID, favorite: Bool) async throws {
        guard let index = bundles.firstIndex(where: { $0.ride.id == rideId }) else { return }
        bundles[index].ride.favorite = favorite
    }

    func deleteRide(id: UUID) async throws {
        bundles.removeAll { $0.ride.id == id }
    }

    func fetchAISummary(rideId: UUID) async throws -> RideAISummary? {
        // Sample so previews show the AI card.
        RideAISummary(
            id: UUID(), rideId: rideId,
            summary: "Smooth ride on mostly well-maintained roads. A short stretch had cracked pavement near the midpoint.",
            accessibilityScore: 78, accessibilityRating: "good",
            potholesDetected: true, potholeCount: 2,
            labels: ["bike_lane", "urban"],
            observations: ["Clear bike lane for most of the route", "Cracked pavement near midpoint"],
            roadHazards: ["cracked_pavement"],
            recommendedMapTags: ["bike_lane"]
        )
    }

    func fetchPhotos(rideId: UUID) async throws -> [RidePhoto] {
        // No remote images in previews.
        []
    }
}
