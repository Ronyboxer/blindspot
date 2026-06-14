//
//  MockAuthService.swift
//  Blind Spot
//
//  Firebase-free `AuthService` for SwiftUI previews. Starts signed-in (or not)
//  and never touches Firebase, so previews render without configuration.
//

import Foundation
import UIKit

@MainActor
@Observable
final class MockAuthService: AuthService {

    private(set) var currentUserId: String?
    private(set) var currentEmail: String?
    private(set) var currentDisplayName: String?

    init(userId: String? = nil, email: String? = nil, displayName: String? = nil) {
        self.currentUserId = userId
        self.currentEmail = email
        self.currentDisplayName = displayName
    }

    func start() {}

    func signIn(email: String, password: String) async throws {
        currentUserId = "mock-user"
        currentEmail = email
    }

    func signUp(email: String, password: String) async throws {
        currentUserId = "mock-user"
        currentEmail = email
    }

    func signInWithGoogle(presenting: UIViewController) async throws {
        currentUserId = "mock-user"
        currentEmail = "rider@example.com"
        currentDisplayName = "Rider"
    }

    func signOut() throws {
        currentUserId = nil
        currentEmail = nil
        currentDisplayName = nil
    }

    func currentAccessToken() async -> String? { nil }
}
