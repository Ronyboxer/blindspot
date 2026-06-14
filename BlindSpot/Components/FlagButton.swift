//
//  FlagButton.swift
//  Blind Spot
//
//  The big circular hi-vis "flag a hazard" button for the Record screen.
//  Large tap target, bold yellow disc with a flag glyph + caption.
//

import SwiftUI

struct FlagButton: View {
    var title: String = "FLAG HAZARD"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 40, weight: .heavy))
                Text(title)
                    .font(.custom(BSFont.monoBold, size: 13))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.bsBlack)
            .frame(width: 150, height: 150)
        }
        .buttonStyle(FlagButtonStyle())
        .accessibilityLabel("Flag a hazard")
    }
}

private struct FlagButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.bsPrimaryDeep : Color.bsPrimary)
            )
            .overlay(
                Circle().stroke(Color.bsPrimaryBright.opacity(0.5), lineWidth: 3)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.bsBlack.ignoresSafeArea()
        FlagButton {}
    }
    .preferredColorScheme(.dark)
}
