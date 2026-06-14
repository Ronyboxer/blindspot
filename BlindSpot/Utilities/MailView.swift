//
//  MailView.swift
//  Blind Spot
//
//  A thin SwiftUI wrapper around MFMailComposeViewController so we can present
//  the system mail composer pre-filled. The user reviews and taps Send — nothing
//  is sent automatically.
//

import SwiftUI
import MessageUI

struct MailView: UIViewControllerRepresentable {
    let recipients: [String]
    let subject: String
    let body: String
    var onFinish: () -> Void = {}

    /// True if the device can send mail (a Mail account is set up).
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(recipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                  didFinishWith result: MFMailComposeResult,
                                  error: Error?) {
            controller.dismiss(animated: true) { self.onFinish() }
        }
    }
}
