//
//  AppEnvironment.swift
//  Blind Spot
//
//  The dependency container + composition root. Holds every service behind its
//  protocol so the rest of the app is decoupled from concrete implementations
//  (Firebase, Supabase, CoreLocation, CoreMotion). It also owns session state:
//  the signed-in user's `profile`, loaded from Supabase.
//
//  Two factories:
//   - `live()`    — real Firebase + Supabase + CoreLocation/CoreMotion.
//   - `preview`   — all mocks, for SwiftUI previews (never touches Firebase).
//
//  `@MainActor` because it publishes UI state and coordinates main-actor services.
//

import Foundation
import Observation
import FirebaseAuth   // composition root only: builds the Supabase token closure

@MainActor
@Observable
final class AppEnvironment {

    // MARK: Services (protocols — the seams)

    let hazardRepository: HazardRepository
    let rideRepository: RideRepository
    let profileRepository: ProfileRepository
    let authService: AuthService
    let locationService: LocationService
    let motionService: MotionService

    /// Shared ride lifecycle, driven by both the UI and the Raspberry Pi.
    let rideController: RideController
    /// Local HTTP server the Pi calls to start/stop a ride (port 8787).
    /// Legacy hotspot path — kept but not auto-started; BLE is the current path.
    let rideControlServer: RideControlServer
    /// BLE peripheral the Pi connects to over Bluetooth (current Pi integration).
    let ridePeripheralServer: RidePeripheralServer

    // MARK: Session state

    /// The signed-in rider's profile, loaded from Supabase. Nil when signed out
    /// or before onboarding has created a row.
    var profile: Profile?
    private(set) var isLoadingProfile = false

    init(
        hazardRepository: HazardRepository,
        rideRepository: RideRepository,
        profileRepository: ProfileRepository,
        authService: AuthService,
        locationService: LocationService,
        motionService: MotionService
    ) {
        self.hazardRepository = hazardRepository
        self.rideRepository = rideRepository
        self.profileRepository = profileRepository
        self.authService = authService
        self.locationService = locationService
        self.motionService = motionService

        // One ride controller shared by the UI and the Pi HTTP server.
        let controller = RideController(
            rideRepository: rideRepository,
            hazardRepository: hazardRepository,
            locationService: locationService,
            motionService: motionService
        )
        self.rideController = controller
        let server = RideControlServer()
        server.delegate = controller
        self.rideControlServer = server

        // BLE peripheral (current Pi integration) — same delegate, so BLE drives
        // the same ride lifecycle.
        let ble = RidePeripheralServer()
        ble.delegate = controller
        self.ridePeripheralServer = ble
    }

    // MARK: Session helpers

    /// True once we know the user is signed in but has no profile yet.
    var needsOnboarding: Bool {
        authService.isSignedIn && profile == nil && !isLoadingProfile
    }

    /// Load the current user's profile from Supabase. Called when auth state
    /// changes (see RootView).
    func refreshProfile() async {
        guard let uid = authService.currentUserId else {
            profile = nil
            return
        }
        isLoadingProfile = true
        defer { isLoadingProfile = false }
        do {
            profile = try await profileRepository.fetchProfile(userId: uid)
        } catch {
            // Network/RLS error — treat as "no profile loaded" for now.
            profile = nil
        }
    }

    /// Persist a profile (onboarding / profile edits) and update local state.
    func saveProfile(_ profile: Profile) async throws {
        try await profileRepository.upsertProfile(profile)
        self.profile = profile
    }

    func signOut() {
        try? authService.signOut()
        profile = nil
    }

    // MARK: - Factories

    /// Real services: Firebase auth, Supabase data, live CoreLocation/CoreMotion.
    static func live() -> AppEnvironment {
        let auth = FirebaseAuthService()

        // Supabase authenticates each request with the current Firebase ID token
        // (Third-Party Auth). Reads Firebase directly so the closure captures
        // nothing non-Sendable.
        let client = SupabaseClientProvider.make(tokenProvider: {
            guard let user = Auth.auth().currentUser else { return nil }
            return try? await user.getIDToken()
        })

        // Row owner for Supabase writes = the Firebase UID.
        let uid: @Sendable () -> String? = { Auth.auth().currentUser?.uid }

        return AppEnvironment(
            hazardRepository: SupabaseHazardRepository(client: client, userId: uid),
            rideRepository: SupabaseRideRepository(client: client, userId: uid),
            profileRepository: SupabaseProfileRepository(client: client),
            authService: auth,
            locationService: LiveLocationService(),
            motionService: LiveMotionService()
        )
    }

    /// All-mock environment for SwiftUI previews.
    static var preview: AppEnvironment {
        AppEnvironment(
            hazardRepository: MockHazardRepository(),
            rideRepository: MockRideRepository(),
            profileRepository: MockProfileRepository(),
            authService: MockAuthService(userId: "preview-user", email: "rider@example.com"),
            locationService: MockLocationService(),
            motionService: MockMotionService()
        )
    }
}
