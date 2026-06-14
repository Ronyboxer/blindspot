//
//  UIApplication+TopVC.swift
//  Blind Spot
//
//  Helper to find the top-most view controller, needed to present Google
//  Sign-In from SwiftUI (GoogleSignIn requires a presenting UIViewController).
//

import UIKit

extension UIApplication {
    /// The currently visible view controller in the foreground active scene.
    func topViewController() -> UIViewController? {
        let scene = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        let keyWindow = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
