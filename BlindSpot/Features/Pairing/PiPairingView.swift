//
//  PiPairingView.swift
//  Blind Spot
//
//  Small status/control screen for the Raspberry Pi BLE integration. Toggle
//  advertising (pairing mode) and watch connection + command/response activity.
//  Reachable from Profile → "Pi Pairing (Bluetooth)".
//
//  Keep the app foregrounded on this/the ride screen during a demo — BLE
//  advertising is reliable in the foreground; iOS heavily throttles it in the
//  background.
//

import SwiftUI

struct PiPairingView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var advertising = false

    private var status: BLEStatus { environment.ridePeripheralServer.status }

    var body: some View {
        ZStack {
            Color.bsBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    toggleCard
                    statusCard
                    logCard
                }
                .padding(16)
            }
        }
        .navigationTitle("Pi Pairing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.bsBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Reflect actual advertising state if it changes underneath us.
        .onChange(of: status.isAdvertising) { _, new in advertising = new }
        .onAppear { advertising = status.isAdvertising }
    }

    // MARK: Pairing toggle

    private var toggleCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { advertising },
                    set: { on in
                        advertising = on
                        if on { environment.ridePeripheralServer.startAdvertising() }
                        else  { environment.ridePeripheralServer.stopAdvertising() }
                    }
                )) {
                    Text("Bluetooth Pairing")
                        .font(.bsHeadline)
                        .foregroundStyle(Color.bsWhite)
                }
                .tint(.bsPrimary)

                Text("When on, the app advertises over Bluetooth so your Raspberry Pi can start and stop rides. Keep the app open during a ride.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bsWhite.opacity(0.5))
            }
        }
    }

    // MARK: Live status

    private var statusCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("STATUS")
                    .font(.bsCaption).tracking(1.2)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                row("Bluetooth", status.poweredOn ? "On" : "Off",
                    ok: status.poweredOn)
                row("Advertising", status.isAdvertising ? "Yes" : "No",
                    ok: status.isAdvertising)
                row("Pi connected", status.connectedDevice ?? "—",
                    ok: status.connectedDevice != nil)
                row("Active ride", status.activeRideId.map { String($0.prefix(8)) } ?? "—",
                    ok: status.activeRideId != nil)
                row("Last command", status.lastCommand ?? "—", ok: nil)
                row("Last response", status.lastResponse ?? "—", ok: nil, mono: true)
            }
        }
    }

    private func row(_ label: String, _ value: String, ok: Bool?, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color.bsWhite.opacity(0.6))
            Spacer()
            Text(value)
                .font(mono ? .custom(BSFont.monoMedium, size: 11) : .system(size: 13, weight: .semibold))
                .foregroundStyle(ok == nil ? Color.bsWhite : (ok! ? Color.bsGood : Color.bsWhite.opacity(0.4)))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 200, alignment: .trailing)
        }
    }

    // MARK: Debug log

    private var logCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("LOG")
                    .font(.bsCaption).tracking(1.2)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                if status.log.isEmpty {
                    Text("No activity yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.bsWhite.opacity(0.4))
                } else {
                    ForEach(Array(status.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.custom(BSFont.monoRegular, size: 11))
                            .foregroundStyle(Color.bsWhite.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { PiPairingView() }
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
