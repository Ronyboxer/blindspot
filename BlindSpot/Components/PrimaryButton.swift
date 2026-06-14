//
//  PrimaryButton.swift
//  Blind Spot
//
//  The primary call-to-action button: bold yellow fill, black text, large tap
//  target (≥56pt). Pressed state darkens to `bsPrimaryDeep`.
//

import SwiftUI

struct PrimaryButton: View {
    let title: String
    /// Optional SF Symbol shown before the title.
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .bold))
                }
                Text(title)
                    .font(.bsButton)            // JetBrains Mono bold
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity, minHeight: 56)   // large tap target
            .foregroundStyle(Color.bsBlack)              // black ink on coral
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

/// Custom style so we can react to the pressed state with the deep-yellow token.
private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.bsPrimaryDeep : Color.bsPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            // Subtle press feedback.
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.bsBlack.ignoresSafeArea()
        VStack(spacing: 16) {
            PrimaryButton(title: "START RIDE", systemImage: "bicycle") {}
            PrimaryButton(title: "STOP") {}
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
