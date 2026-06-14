//
//  RidesViewModel.swift
//  Blind Spot
//
//  Backs the Rides list. Loads ride summaries from the injected `RideRepository`.
//

import Foundation
import Observation

@MainActor
@Observable
final class RidesViewModel {

    private(set) var rides: [Ride] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    func load(using repository: RideRepository) async {
        isLoading = true
        errorMessage = nil
        do {
            rides = try await repository.fetchRides()
        } catch {
            errorMessage = "Couldn't load rides."
        }
        isLoading = false
    }

    /// Star/unstar a ride. Optimistic; reverts on failure.
    func toggleFavorite(id: UUID, using repository: RideRepository) async {
        guard let index = rides.firstIndex(where: { $0.id == id }) else { return }
        let newValue = !rides[index].favorite
        rides[index].favorite = newValue
        do {
            try await repository.setFavorite(rideId: id, favorite: newValue)
        } catch {
            rides[index].favorite = !newValue
            errorMessage = "Couldn't update favorite."
        }
    }

    /// Delete a ride. Optimistically removes it from the list, then deletes
    /// server-side; reloads on failure to restore the true state.
    func delete(id: UUID, using repository: RideRepository) async {
        let previous = rides
        rides.removeAll { $0.id == id }
        do {
            try await repository.deleteRide(id: id)
        } catch {
            rides = previous
            errorMessage = "Couldn't delete that ride."
        }
    }
}
