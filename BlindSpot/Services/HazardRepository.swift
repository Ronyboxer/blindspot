//
//  HazardRepository.swift
//  Blind Spot
//
//  The abstraction (the "seam") between the UI and wherever hazards come from.
//  Today: an in-memory mock. Later: Supabase/SQL — by writing a new conformer
//  and swapping it in `AppEnvironment`. Views/view models never change.
//
//  Methods are `async throws` so the mock and the future networked impl share
//  one signature.
//

import Foundation

protocol HazardRepository {
    /// All known hazards (the map reads these). Crowd-sourced across riders.
    func fetchHazards() async throws -> [Hazard]

    /// Report a new hazard (e.g. when the rider flags one during a ride).
    func reportHazard(_ hazard: Hazard) async throws

    /// Remove a hazard from the map.
    func deleteHazard(id: UUID) async throws
}
