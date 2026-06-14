//
//  SupabaseHazardRepository.swift
//  Blind Spot
//
//  `HazardRepository` backed by Supabase. The `hazards` table is crowd-sourced:
//  any signed-in rider can read all hazards (the map), but can only insert their
//  own. Hazards are created when a rider flags one during a ride.
//

import Foundation
import Supabase

final class SupabaseHazardRepository: HazardRepository {

    private let client: SupabaseClient
    private let userId: @Sendable () -> String?

    init(client: SupabaseClient, userId: @escaping @Sendable () -> String?) {
        self.client = client
        self.userId = userId
    }

    func fetchHazards() async throws -> [Hazard] {
        let rows: [HazardRow] = try await client
            .from("hazards")
            .select()
            .order("first_reported_at", ascending: false)
            .limit(500)
            .execute()
            .value
        return rows.compactMap { $0.toDomain() }
    }

    func reportHazard(_ hazard: Hazard) async throws {
        try await client.from("hazards").insert(HazardRow(hazard, userId: userId())).execute()
    }

    func deleteHazard(id: UUID) async throws {
        try await client.from("hazards").delete().eq("id", value: id.uuidString).execute()
    }

    // MARK: - DB row

    private struct HazardRow: Codable {
        let id: UUID
        let user_id: String?
        let lat: Double
        let lng: Double
        let type: String
        let severity: String
        let status: String
        let confirm_count: Int
        let first_reported_at: String
        let last_confirmed_at: String?

        init(_ h: Hazard, userId: String?) {
            id = h.id; user_id = userId
            lat = h.lat; lng = h.lng
            type = h.type.rawValue; severity = h.severity.rawValue; status = h.status.rawValue
            confirm_count = h.confirmCount
            first_reported_at = SupabaseDate.string(from: h.firstReportedAt)
            last_confirmed_at = h.lastConfirmedAt.map(SupabaseDate.string(from:))
        }

        func toDomain() -> Hazard? {
            // Skip rows with unknown enum values rather than crash.
            guard let t = HazardType(rawValue: type),
                  let sev = Severity(rawValue: severity),
                  let st = HazardStatus(rawValue: status) else { return nil }
            return Hazard(id: id, lat: lat, lng: lng, type: t, severity: sev, status: st,
                          confirmCount: confirm_count,
                          firstReportedAt: SupabaseDate.date(from: first_reported_at) ?? Date(),
                          lastConfirmedAt: last_confirmed_at.flatMap(SupabaseDate.date(from:)))
        }
    }
}
