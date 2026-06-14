//
//  HazardBadge.swift
//  Blind Spot
//
//  Renders a hazard by TYPE (the severity / minor·moderate·severe system has
//  been removed). Two styles:
//   - `.pin`  — compact circular map marker (coral disc + type icon).
//   - `.full` — coral type icon + type label, for inline lists.
//

import SwiftUI

struct HazardBadge: View {
    let type: HazardType
    var style: Style = .full

    enum Style {
        case pin
        case full
    }

    var body: some View {
        switch style {
        case .pin:  pin
        case .full: full
        }
    }

    // MARK: - Map pin

    private var pin: some View {
        ZStack {
            Circle()
                .fill(type.color)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Color.bsBlack, lineWidth: 2))
                .shadow(radius: 3)
            Image(systemName: type.symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.bsBlack)
        }
        .accessibilityElement()
        .accessibilityLabel(type.displayName)
    }

    // MARK: - Full inline badge

    private var full: some View {
        HStack(spacing: 8) {
            Image(systemName: type.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(type.color)
            Text(type.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.bsWhite)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.bsCharcoal)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(type.displayName)
    }
}

#Preview {
    ZStack {
        Color.bsBlack.ignoresSafeArea()
        VStack(spacing: 20) {
            HStack(spacing: 16) {
                HazardBadge(type: .pothole, style: .pin)
                HazardBadge(type: .glass, style: .pin)
                HazardBadge(type: .debris, style: .pin)
            }
            HazardBadge(type: .pothole)
            HazardBadge(type: .water)
            HazardBadge(type: .construction)
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
