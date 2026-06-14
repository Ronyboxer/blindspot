//
//  ProfileRepository.swift
//  Blind Spot
//
//  The seam for rider-profile persistence. Real implementation is Supabase
//  (`SupabaseProfileRepository`); a mock backs previews. Swapping is invisible
//  to views/view models.
//

import Foundation

protocol ProfileRepository {
    /// Fetch the profile for a user id (Firebase UID). Nil if none exists yet
    /// (i.e. the user hasn't completed onboarding).
    func fetchProfile(userId: String) async throws -> Profile?

    /// Create or update the user's profile row.
    func upsertProfile(_ profile: Profile) async throws
}

// MARK: - Mock (previews / offline)

/// In-memory profile store for previews and offline development.
final class MockProfileRepository: ProfileRepository {
    private var profiles: [String: Profile] = [:]

    init(seed: [Profile] = []) {
        for p in seed { profiles[p.id] = p }
    }

    func fetchProfile(userId: String) async throws -> Profile? {
        profiles[userId]
    }

    func upsertProfile(_ profile: Profile) async throws {
        profiles[profile.id] = profile
    }
}
