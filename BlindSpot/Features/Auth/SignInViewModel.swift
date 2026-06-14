//
//  SignInViewModel.swift
//  Blind Spot
//
//  Backs the sign-in / create-account screen. Talks only to the `AuthService`
//  protocol; on success the auth-state listener flips RootView to the app.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SignInViewModel {

    enum Mode { case signIn, signUp }

    var mode: Mode = .signIn
    var email = ""
    var password = ""

    private(set) var isWorking = false
    private(set) var errorMessage: String?

    var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && !isWorking
    }

    var submitTitle: String { mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT" }
    var togglePrompt: String {
        mode == .signIn ? "New here? Create an account" : "Have an account? Sign in"
    }

    func toggleMode() {
        mode = (mode == .signIn) ? .signUp : .signIn
        errorMessage = nil
    }

    func submit(using auth: AuthService) async {
        guard canSubmit else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            switch mode {
            case .signIn: try await auth.signIn(email: email, password: password)
            case .signUp: try await auth.signUp(email: email, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle(using auth: AuthService) async {
        guard let presenter = UIApplication.shared.topViewController() else {
            errorMessage = "Couldn't present Google Sign-In."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.signInWithGoogle(presenting: presenter)
        } catch {
            // GoogleSignIn throws a cancellation error if the user backs out — ignore that.
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn" && ns.code == -5 { return }  // canceled
            errorMessage = error.localizedDescription
        }
    }
}
