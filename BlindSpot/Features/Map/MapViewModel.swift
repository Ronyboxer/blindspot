//
//  MapViewModel.swift
//  Blind Spot
//
//  Loads hazards from the injected `HazardRepository` for the Map screen.
//  Knows nothing about WHERE hazards come from — only the protocol.
//

import Foundation
import Observation

@MainActor
@Observable
final class MapViewModel {

    /// The hazards currently shown on the map.
    private(set) var hazards: [Hazard] = []

    /// True while the initial fetch is in flight (drives a small spinner).
    private(set) var isLoading = false

    /// Set if a fetch failed (the future networked repo can throw).
    private(set) var errorMessage: String?

    /// The repository is passed in from the view (which reads it from the
    /// app environment). The VM stays decoupled from concrete types.
    func load(using repository: HazardRepository) async {
        isLoading = true
        errorMessage = nil
        do {
            hazards = try await repository.fetchHazards()
        } catch {
            errorMessage = "Couldn't load hazards."
        }
        isLoading = false
    }
}
