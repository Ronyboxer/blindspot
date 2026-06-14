//
//  RootView.swift
//  Blind Spot
//
//  Decides what the rider sees at launch:
//    1. Not signed in            → SignInView (Firebase email / Google)
//    2. Signed in, loading       → spinner
//    3. Signed in, no profile    → OnboardingView (creates the Supabase profile)
//    4. Signed in, has profile   → the main tab bar
//
//  Auth state lives on `environment.authService`; the profile is loaded from
//  Supabase whenever the signed-in user id changes.
//

import SwiftUI

struct RootView: View {

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            if !environment.authService.isSignedIn {
                SignInView()
            } else if environment.isLoadingProfile {
                loading
            } else if environment.profile == nil {
                OnboardingView()
            } else {
                RootTabView()
            }
        }
        .animation(.easeInOut, value: environment.authService.currentUserId)
        .animation(.easeInOut, value: environment.profile)
        // Start the Firebase auth listener (Firebase is configured by now), and
        // reload the profile whenever the signed-in user changes.
        .task(id: environment.authService.currentUserId) {
            environment.authService.start()
            await environment.refreshProfile()
        }
    }

    private var loading: some View {
        ZStack {
            Color.bsBlack.ignoresSafeArea()
            ProgressView().tint(.bsPrimary)
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
