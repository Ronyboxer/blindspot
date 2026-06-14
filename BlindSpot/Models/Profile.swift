//
//  Profile.swift
//  Blind Spot
//
//  The rider's profile. Most of this is collected during onboarding. Auth +
//  server persistence arrive with the data layer; for now it's stored locally
//  (UserDefaults via AppEnvironment) so it survives app launches.
//

import Foundation

struct Profile: Codable, Identifiable, Hashable {
    /// The Firebase UID — also the primary key of the Supabase `profiles` row.
    /// Empty string until the user is signed in.
    let id: String
    var displayName: String?
    var email: String?
    var phone: String?
    /// Self-assessed cycling ability (onboarding).
    var skillLevel: BikingSkill?
    /// Typical rides per week (onboarding).
    var weeklyFrequency: RideFrequency?
    /// Phone/contact string for the crash-SOS flow.
    var emergencyContact: String?

    init(
        id: String = "",
        displayName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        skillLevel: BikingSkill? = nil,
        weeklyFrequency: RideFrequency? = nil,
        emergencyContact: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.phone = phone
        self.skillLevel = skillLevel
        self.weeklyFrequency = weeklyFrequency
        self.emergencyContact = emergencyContact
    }
}
