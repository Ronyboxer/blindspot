//
//  BSCard.swift
//  Blind Spot
//
//  A standard card surface: graphite background, rounded corners, padding.
//  Wraps arbitrary content via a `@ViewBuilder`.
//

import SwiftUI

struct BSCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bsGraphite)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    ZStack {
        Color.bsBlack.ignoresSafeArea()
        BSCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card title").font(.bsHeadline).foregroundStyle(Color.bsWhite)
                Text("Some supporting copy.").font(.bsBody).foregroundStyle(Color.bsWhite.opacity(0.7))
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
