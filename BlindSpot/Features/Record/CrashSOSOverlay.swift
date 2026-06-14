//
//  CrashSOSOverlay.swift
//  Blind Spot
//
//  Full-screen, alarming crash-SOS countdown. Big bright-yellow timer with a
//  Dismiss ("I'm OK") action. When the countdown expires it flips to a MOCK
//  "SOS sent to emergency contact" confirmation. Nothing is actually sent.
//
//  Driven entirely by `RecordRideViewModel` state.
//

import SwiftUI

struct CrashSOSOverlay: View {
    let countdown: Int
    let sent: Bool
    let emergencyContact: String?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Heavy scrim so the alarm dominates.
            Color.bsBlack.opacity(0.94).ignoresSafeArea()

            if sent {
                sentConfirmation
            } else {
                countdownView
            }
        }
        // Pulse the whole alarm so it reads as urgent.
        .transition(.opacity)
    }

    // MARK: Countdown

    private var countdownView: some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60, weight: .heavy))
                .foregroundStyle(Color.bsPrimaryBright)

            Text("CRASH DETECTED")
                .font(.custom(BSFont.monoExtraBold, size: 26))
                .tracking(2)
                .foregroundStyle(Color.bsWhite)

            Text("Sending SOS in")
                .font(.bsBody)
                .foregroundStyle(Color.bsWhite.opacity(0.7))

            // The big alarming number.
            Text("\(countdown)")
                .font(.custom(BSFont.monoExtraBold, size: 120))
                .foregroundStyle(Color.bsPrimaryBright)
                .contentTransition(.numericText())
                .animation(.snappy, value: countdown)

            if let emergencyContact, !emergencyContact.isEmpty {
                Text("Will alert: \(emergencyContact)")
                    .font(.bsCaption)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))
            } else {
                Text("No emergency contact set")
                    .font(.bsCaption)
                    .foregroundStyle(Color.bsModerate)
            }

            // Big "I'm OK" cancel — the most important escape hatch.
            Button(action: onDismiss) {
                Text("I'M OK — CANCEL")
                    .font(.bsButton)
                    .foregroundStyle(Color.bsBlack)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(Color.bsPrimaryBright)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 8)
        }
        .padding(28)
    }

    // MARK: Sent confirmation (mock)

    private var sentConfirmation: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, weight: .heavy))
                .foregroundStyle(Color.bsGood)

            Text("SOS SENT")
                .font(.custom(BSFont.monoExtraBold, size: 28))
                .tracking(2)
                .foregroundStyle(Color.bsWhite)

            Text(emergencyContact.map { "Emergency contact \($0) was notified." }
                 ?? "Emergency contact was notified.")
                .font(.bsBody)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.bsWhite.opacity(0.7))

            // Make clear this is a mock for the foundation milestone.
            Text("(Mock — no message was actually sent.)")
                .font(.bsCaption)
                .foregroundStyle(Color.bsWhite.opacity(0.4))

            Button(action: onDismiss) {
                Text("DISMISS")
                    .font(.bsButton)
                    .foregroundStyle(Color.bsBlack)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.bsPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 8)
        }
        .padding(28)
    }
}

#Preview("Countdown") {
    CrashSOSOverlay(countdown: 12, sent: false, emergencyContact: "Alex (555) 123-4567") {}
        .preferredColorScheme(.dark)
}

#Preview("Sent") {
    CrashSOSOverlay(countdown: 0, sent: true, emergencyContact: "Alex (555) 123-4567") {}
        .preferredColorScheme(.dark)
}
