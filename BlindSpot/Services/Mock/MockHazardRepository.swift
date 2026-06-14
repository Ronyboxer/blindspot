//
//  MockHazardRepository.swift
//  Blind Spot
//
//  In-memory hazard source for the foundation milestone. Seeded from SampleData.
//  Conforms to `HazardRepository`, so the future Supabase impl is a drop-in
//  replacement.
//

import Foundation

/// `final class` (reference type) so the same store is shared via `AppEnvironment`.
final class MockHazardRepository: HazardRepository {

    /// The in-memory store. Seeded once at construction.
    private var hazards: [Hazard]

    init() {
        self.hazards = SampleData.makeHazards()
    }

    func fetchHazards() async throws -> [Hazard] {
        // A tiny artificial delay would simulate the network; we keep it instant
        // for snappy previews. The real impl will actually await a request.
        return hazards
    }

    func reportHazard(_ hazard: Hazard) async throws {
        hazards.append(hazard)
    }

    func deleteHazard(id: UUID) async throws {
        hazards.removeAll { $0.id == id }
    }
}
