//
//  StatTile.swift
//  Blind Spot
//
//  A single readout: a big monospaced number over a small uppercase label.
//  Used for ride stats (recap) and live telemetry (record). The monospaced
//  number gives the instrument-panel feel and keeps columns aligned.
//

import SwiftUI

struct StatTile: View {
    /// The big value, already formatted (e.g. "12.4", "00:42").
    let value: String
    /// The small label under it (e.g. "KM", "DURATION"). Rendered uppercase.
    let label: String
    /// Optional unit shown small next to the value (e.g. "mph").
    var unit: String? = nil
    /// Optional accent for the value (defaults to brand yellow).
    var valueColor: Color = .bsPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.bsStatLarge)
                    .foregroundStyle(valueColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.bsStatSmall)
                        .foregroundStyle(Color.bsWhite.opacity(0.6))
                }
            }
            Text(label.uppercased())
                .font(.bsCaption)
                .tracking(1.2)
                .foregroundStyle(Color.bsWhite.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        Color.bsBlack.ignoresSafeArea()
        HStack {
            StatTile(value: "12.4", label: "Distance", unit: "mi")
            StatTile(value: "00:42", label: "Duration")
            StatTile(value: "22", label: "Avg Speed", unit: "mph")
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
