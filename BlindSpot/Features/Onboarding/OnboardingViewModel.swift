//
//  OnboardingViewModel.swift
//  Blind Spot
//
//  Drives the first-run onboarding flow. Collects the rider's name, email,
//  phone, skill level, and weekly riding frequency across a few steps, then
//  writes a `Profile` into the app environment and marks onboarding complete.
//
//  Pure state + navigation logic; the view renders each step.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {

    /// Ordered steps of the flow. `welcome` is the intro; the rest collect data.
    enum Step: Int, CaseIterable {
        case welcome
        case name
        case email
        case phone
        case skill
        case frequency

        /// The question-collecting steps (excludes the welcome screen), used to
        /// compute progress through the form.
        static var formSteps: [Step] { allCases.filter { $0 != .welcome } }
    }

    private(set) var step: Step = .welcome

    // MARK: - Draft fields (bound to the inputs)

    var name = ""
    var email = ""
    var phone = ""
    var skill: BikingSkill?
    var frequency: RideFrequency?

    /// Set while the final profile is being written to Supabase.
    private(set) var isSaving = false
    private(set) var saveError: String?

    // MARK: - Progress

    /// 0...1 progress across the FORM steps (welcome contributes 0).
    var progress: Double {
        guard step != .welcome else { return 0 }
        let total = Double(Step.formSteps.count)
        let index = Double((Step.formSteps.firstIndex(of: step) ?? 0) + 1)
        return index / total
    }

    var isFirstStep: Bool { step == .welcome }
    var isLastStep: Bool { step == Step.allCases.last }

    /// Whether the current step's input is valid enough to advance.
    var canAdvance: Bool {
        switch step {
        case .welcome:   return true
        case .name:      return !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .email:     return isValidEmail(email)
        case .phone:     return isValidPhone(phone)
        case .skill:     return skill != nil
        case .frequency: return frequency != nil
        }
    }

    // MARK: - Navigation

    func advance() {
        guard canAdvance else { return }
        let next = min(step.rawValue + 1, Step.allCases.count - 1)
        step = Step(rawValue: next) ?? step
    }

    func back() {
        let prev = max(step.rawValue - 1, 0)
        step = Step(rawValue: prev) ?? step
    }

    /// Prefill from the signed-in Firebase user (Google gives name + email;
    /// email sign-up gives email). Only fills empty fields.
    func prefill(from auth: AuthService) {
        if name.isEmpty, let displayName = auth.currentDisplayName { name = displayName }
        if email.isEmpty, let userEmail = auth.currentEmail { email = userEmail }
    }

    /// Build the profile (keyed by Firebase UID) and persist it to Supabase.
    /// On success, `environment.profile` is set, which routes into the main app.
    func finish(into environment: AppEnvironment) async {
        guard let uid = environment.authService.currentUserId else {
            saveError = "Not signed in."
            return
        }

        let profile = Profile(
            id: uid,
            displayName: name.trimmingCharacters(in: .whitespaces),
            email: email.trimmingCharacters(in: .whitespaces),
            phone: phone.trimmingCharacters(in: .whitespaces),
            skillLevel: skill,
            weeklyFrequency: frequency,
            // Preserve an emergency contact if one was somehow already set.
            emergencyContact: environment.profile?.emergencyContact
        )

        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await environment.saveProfile(profile)
        } catch {
            saveError = "Couldn't save your profile. Check your connection and try again."
        }
    }

    // MARK: - Lightweight validation

    private func isValidEmail(_ value: String) -> Bool {
        // Good-enough check for onboarding: something@something.tld
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidPhone(_ value: String) -> Bool {
        // Require at least 7 digits; ignore spaces, dashes, parens, +.
        let digits = value.filter(\.isNumber)
        return digits.count >= 7
    }
}
