//
//  SupabaseProfileRepository.swift
//  Blind Spot
//
//  `ProfileRepository` backed by Supabase Postgres (the `profiles` table). Maps
//  between the domain `Profile` (camelCase) and the DB row (snake_case) via a
//  private `ProfileRow`, so the domain model stays free of DB concerns.
//

import Foundation
import Supabase

final class SupabaseProfileRepository: ProfileRepository {

    private let client: SupabaseClient
    private let table = "profiles"

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchProfile(userId: String) async throws -> Profile? {
        // Fetch 0 or 1 rows for this user. Using an array + first avoids throwing
        // when the user has no profile yet (pre-onboarding).
        let rows: [ProfileRow] = try await client
            .from(table)
            .select()
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first?.toDomain()
    }

    func upsertProfile(_ profile: Profile) async throws {
        let row = ProfileRow(from: profile)
        try await client
            .from(table)
            .upsert(row)
            .execute()
    }

    // MARK: - DB row mapping

    /// Mirrors the `profiles` table columns. `created_at` / `updated_at` are
    /// server-managed, so they're decode-only (optional) and never written.
    private struct ProfileRow: Codable {
        let id: String
        let display_name: String?
        let email: String?
        let phone: String?
        let skill_level: String?
        let weekly_frequency: String?
        let emergency_contact: String?

        init(from p: Profile) {
            id = p.id
            display_name = p.displayName
            email = p.email
            phone = p.phone
            skill_level = p.skillLevel?.rawValue
            weekly_frequency = p.weeklyFrequency?.rawValue
            emergency_contact = p.emergencyContact
        }

        func toDomain() -> Profile {
            Profile(
                id: id,
                displayName: display_name,
                email: email,
                phone: phone,
                skillLevel: skill_level.flatMap(BikingSkill.init(rawValue:)),
                weeklyFrequency: weekly_frequency.flatMap(RideFrequency.init(rawValue:)),
                emergencyContact: emergency_contact
            )
        }
    }
}
