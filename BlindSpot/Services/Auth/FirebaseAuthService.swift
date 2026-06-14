//
//  FirebaseAuthService.swift
//  Blind Spot
//
//  Firebase-backed `AuthService`: email/password + Google Sign-In. Exposes the
//  Firebase ID token so the Supabase client can authenticate as this user
//  (Supabase Third-Party Auth → Firebase).
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor
@Observable
final class FirebaseAuthService: AuthService {

    private(set) var currentUserId: String?
    private(set) var currentEmail: String?
    private(set) var currentDisplayName: String?

    private var listenerHandle: AuthStateDidChangeListenerHandle?

    /// Attach the Firebase auth-state listener. Safe to call multiple times;
    /// only attaches once. Must run after `FirebaseApp.configure()`.
    func start() {
        guard listenerHandle == nil else { return }
        // Seed from any already-restored session.
        syncUser(Auth.auth().currentUser)
        listenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Firebase calls this on the main thread; hop to the actor to mutate.
            Task { @MainActor in self?.syncUser(user) }
        }
    }

    private func syncUser(_ user: User?) {
        currentUserId = user?.uid
        currentEmail = user?.email
        currentDisplayName = user?.displayName
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    // MARK: - Google

    func signInWithGoogle(presenting: UIViewController) async throws {
        // Google needs the OAuth client id; Firebase carries it in its options.
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingGoogleClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingGoogleIDToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await Auth.auth().signIn(with: credential)
    }

    // MARK: - Sign out / token

    func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }

    func currentAccessToken() async -> String? {
        guard let user = Auth.auth().currentUser else { return nil }
        return try? await user.getIDToken()
    }

    enum AuthError: LocalizedError {
        case missingGoogleClientID
        case missingGoogleIDToken

        var errorDescription: String? {
            switch self {
            case .missingGoogleClientID: return "Google sign-in isn't configured."
            case .missingGoogleIDToken:  return "Google sign-in failed to return a token."
            }
        }
    }
}
