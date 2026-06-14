//
//  AuthService.swift
//  Blind Spot
//
//  Authentication seam. The app talks to the `AuthService` protocol; the real
//  implementation is Firebase (email/password + Google), and a mock is used for
//  SwiftUI previews so they never touch Firebase.
//
//  Auth state is observable: `currentUserId` / `currentEmail` update when the
//  user signs in or out, which drives `RootView`.
//

import Foundation
import SwiftUI
import UIKit

/// Abstract auth provider. `@MainActor` because it publishes UI state.
@MainActor
protocol AuthService: AnyObject {
    /// The signed-in user's stable id (Firebase UID). Nil when signed out.
    var currentUserId: String? { get }
    /// The signed-in user's email, if known.
    var currentEmail: String? { get }
    /// The signed-in user's display name, if the provider supplied one (Google).
    var currentDisplayName: String? { get }

    var isSignedIn: Bool { get }

    /// Attach the underlying auth-state listener. Call once Firebase is configured
    /// (i.e. from a view's `.task`, not at app-construction time).
    func start()

    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String) async throws
    /// Present Google Sign-In from the given view controller, then sign into Firebase.
    func signInWithGoogle(presenting: UIViewController) async throws
    func signOut() throws

    /// Current provider access token (Firebase ID token) for Supabase requests.
    func currentAccessToken() async -> String?
}

extension AuthService {
    var isSignedIn: Bool { currentUserId != nil }
}
