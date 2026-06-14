//
//  BlindSpotApp.swift
//  Blind Spot
//
//  App entry point.
//
//   - `AppDelegate` runs `FirebaseApp.configure()` at launch (before any view),
//     so Firebase Auth is ready by the time RootView appears.
//   - The dependency container `AppEnvironment.live()` wires the real services
//     (Firebase auth, Supabase data, CoreLocation, CoreMotion) behind protocols.
//   - `onOpenURL` hands Google Sign-In redirects back to the GoogleSignIn SDK.
//   - Dark mode is forced app-wide (dark-first design system).
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

/// Minimal UIKit app delegate, used only to configure Firebase at launch.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct BlindSpotApp: App {

    // Register the app delegate so FirebaseApp.configure() runs at launch.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // The dependency container. Built with real services. AppEnvironment's init
    // does not touch Firebase, so constructing it before configure() is safe.
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .preferredColorScheme(.dark)
                // Complete the Google Sign-In flow when Google redirects back.
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
