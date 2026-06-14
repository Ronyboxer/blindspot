//
//  RecordRideView.swift
//  Blind Spot
//
//  The Record tab. Two states:
//   - IDLE: a big "START RIDE" call to action.
//   - RECORDING: live (simulated) telemetry as StatTiles, the big FlagButton,
//     a STOP button, and a debug "Simulate crash" button.
//
//  On STOP the ride is saved via the repository and we navigate to its recap.
//  The crash-SOS overlay sits on top of everything when active.
//

import SwiftUI

struct RecordRideView: View {

    @Environment(AppEnvironment.self) private var environment

    // Navigation path for pushing the recap after a ride is saved.
    @State private var path: [UUID] = []
    // Shows the hazard-type chooser when flagging.
    @State private var showFlagPicker = false
    // Shows the SOS text composer to the emergency contact.
    @State private var showSOSMessage = false

    // The shared ride lifecycle (also driven by the Raspberry Pi via HTTP).
    private var controller: RideController { environment.rideController }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.bsBlack.ignoresSafeArea()

                switch controller.phase {
                case .idle:      idleState
                case .recording: recordingState
                }
            }
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bsCharcoal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: UUID.self) { rideId in
                // Reached right after a ride → offer the pothole-report email.
                RideRecapView(rideId: rideId, autoPromptEmail: true)
            }
            // Crash-SOS overlay floats above the whole screen when active.
            .overlay {
                if controller.sosActive {
                    CrashSOSOverlay(
                        countdown: controller.sosCountdown,
                        sent: controller.sosSent,
                        emergencyContact: environment.profile?.emergencyContact,
                        onDismiss: { controller.dismissSOS() }
                    )
                }
            }
            // Haptic each time an event is flagged (count goes up). iOS 17 API.
            .sensoryFeedback(.success, trigger: controller.events.count)
            .animation(.easeInOut, value: controller.sosActive)
            // When the SOS countdown completes (not dismissed), text the contact.
            .onChange(of: controller.sosSent) { _, sent in
                if sent { presentSOSMessage() }
            }
            .sheet(isPresented: $showSOSMessage) {
                MessageComposeView(recipients: [emergencyPhone],
                                   body: sosMessageBody) { controller.dismissSOS() }
            }
            // Ask for location up front so the first ride has GPS immediately.
            // (Pi ride control is now over BLE — see Profile → Pi Pairing.)
            .task {
                environment.locationService.requestAuthorization()
            }
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: 28) {
            Spacer()

            // The big, central, tap-to-start control.
            BigStartButton {
                Task { await controller.start() }
            }

            Text("Tap to start your ride")
                .font(.bsBody)
                .foregroundStyle(Color.bsWhite.opacity(0.6))

            // Hint if location is denied — GPS is required for a real ride.
            if environment.locationService.authorizationStatus == .denied {
                Text("Location is off. Enable it in Settings to record rides.")
                    .font(.bsCaption)
                    .foregroundStyle(Color.bsModerate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Recording

    private var recordingState: some View {
        VStack(spacing: 24) {
            // Live telemetry grid.
            BSCard {
                VStack(spacing: 20) {
                    HStack(spacing: 12) {
                        StatTile(value: Format.mph(controller.currentSpeedMPS),
                                 label: "Speed", unit: "mph")
                        StatTile(value: Format.duration(Double(controller.elapsedSeconds)),
                                 label: "Time")
                    }
                    HStack(spacing: 12) {
                        StatTile(value: Format.miles(controller.distanceMeters),
                                 label: "Distance", unit: "mi")
                        // Peak IMU magnitude this ride — proves the accelerometer is live.
                        StatTile(value: String(format: "%.1f", controller.peakIMU),
                                 label: "Peak G", unit: "g")
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // The big hi-vis flag button + transient confirmation.
            ZStack {
                FlagButton {
                    // Choose the hazard type (glass, construction, pothole, …).
                    showFlagPicker = true
                }
                if let confirmation = controller.flagConfirmation {
                    Text(confirmation)
                        .font(.bsCaption)
                        .foregroundStyle(Color.bsBlack)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.bsPrimaryBright)
                        .clipShape(Capsule())
                        .offset(y: 100)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: controller.flagConfirmation)
            .confirmationDialog("Flag a hazard", isPresented: $showFlagPicker, titleVisibility: .visible) {
                ForEach(HazardType.allCases) { type in
                    Button(type.displayName) { controller.flag(type) }
                }
                Button("Cancel", role: .cancel) {}
            }

            Spacer()

            // Surface a save failure instead of dropping the ride silently.
            if let saveError = controller.saveError {
                Text(saveError)
                    .font(.bsCaption)
                    .foregroundStyle(Color.bsSevere)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Stop + debug crash controls.
            VStack(spacing: 12) {
                Button {
                    Task {
                        if let rideId = await controller.stop() {
                            path.append(rideId)   // navigate to recap
                        }
                    }
                } label: {
                    Text("STOP")
                        .font(.bsButton)
                        .foregroundStyle(Color.bsWhite)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.bsGraphite)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.bsSevere, lineWidth: 2)
                        )
                }

                // Debug-only affordance to exercise the crash-SOS flow.
                Button {
                    controller.simulateCrash()
                } label: {
                    Label("Simulate crash", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.bsWhite.opacity(0.5))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - SOS messaging

    /// Phone number digits extracted from the saved emergency contact.
    private var emergencyPhone: String {
        let raw = environment.profile?.emergencyContact ?? ""
        return raw.filter { $0.isNumber || $0 == "+" }
    }

    private var sosMessageBody: String {
        var msg = "🚨 Blind Spot SOS — I may have crashed during a bike ride and didn't respond."
        if let loc = environment.locationService.currentLocation {
            let lat = loc.coordinate.latitude, lng = loc.coordinate.longitude
            msg += "\nMy location: \(String(format: "%.5f, %.5f", lat, lng))"
            msg += "\nhttps://maps.apple.com/?ll=\(lat),\(lng)"
        }
        return msg
    }

    /// Open a pre-filled SOS text to the emergency contact (they tap send).
    private func presentSOSMessage() {
        guard emergencyPhone.count >= 7, MessageComposeView.canSend else { return }
        showSOSMessage = true
    }
}

// MARK: - Big start button

/// The large, central orange circle that starts a ride. Big tap target,
/// pressed state darkens + scales.
private struct BigStartButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "figure.outdoor.cycle")
                    .font(.system(size: 64, weight: .heavy))
                Text("START")
                    .font(.custom(BSFont.monoBold, size: 22))
                    .tracking(3)
            }
            .foregroundStyle(Color.bsBlack)
            .frame(width: 240, height: 240)
        }
        .buttonStyle(BigStartButtonStyle())
        .accessibilityLabel("Start ride")
    }
}

private struct BigStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle().fill(configuration.isPressed ? Color.bsPrimaryDeep : Color.bsPrimary)
            )
            // Soft halo so it reads as the focal point.
            .overlay(
                Circle().stroke(Color.bsPrimaryBright.opacity(0.4), lineWidth: 6)
            )
            .shadow(color: Color.bsPrimary.opacity(0.5), radius: 24)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    RecordRideView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
