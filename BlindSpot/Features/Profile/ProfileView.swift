//
//  ProfileView.swift
//  Blind Spot
//
//  The Profile tab: the rider details collected at onboarding (name, email,
//  phone, skill, weekly frequency) plus the emergency contact, all editable.
//  Edits update the in-memory profile and are saved to Supabase when leaving
//  the tab. Includes a working Sign Out.
//

import SwiftUI

struct ProfileView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var showContactPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bsBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        identityCard
                        ridingCard
                        emergencyCard
                        piPairingCard
                        accountCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Profile")
            .toolbarBackground(Color.bsCharcoal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // Persist any edits to Supabase when the user leaves this tab.
            .onDisappear {
                if let profile = environment.profile {
                    Task { try? await environment.saveProfile(profile) }
                }
            }
        }
    }

    // MARK: Pi pairing (Bluetooth)

    private var piPairingCard: some View {
        NavigationLink {
            PiPairingView()
        } label: {
            BSCard {
                HStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.bsPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pi Pairing (Bluetooth)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.bsWhite)
                        Text(environment.ridePeripheralServer.status.isAdvertising
                             ? "Advertising" : "Off")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.bsWhite.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.bsWhite.opacity(0.4))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Identity (name / email / phone)

    private var identityCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 18) {
                labeledField("DISPLAY NAME", placeholder: "Your name",
                             text: bindingFor(\.displayName),
                             font: .bsHeadline, keyboard: .default, autocap: .words)

                Divider().overlay(Color.bsWhite.opacity(0.1))

                labeledField("EMAIL", placeholder: "you@example.com",
                             text: bindingFor(\.email),
                             font: .bsBody, keyboard: .emailAddress, autocap: .never)

                Divider().overlay(Color.bsWhite.opacity(0.1))

                labeledField("PHONE", placeholder: "(555) 123-4567",
                             text: bindingFor(\.phone),
                             font: .bsBody, keyboard: .phonePad, autocap: .never)
            }
        }
    }

    // MARK: Riding (skill / frequency)

    private var ridingCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 18) {
                pickerRow(label: "SKILL LEVEL",
                          current: environment.profile?.skillLevel?.displayName ?? "Not set") {
                    ForEach(BikingSkill.allCases) { option in
                        Button(option.displayName) { environment.profile?.skillLevel = option }
                    }
                }

                Divider().overlay(Color.bsWhite.opacity(0.1))

                pickerRow(label: "RIDES PER WEEK",
                          current: environment.profile?.weeklyFrequency?.displayName ?? "Not set") {
                    ForEach(RideFrequency.allCases) { option in
                        Button(option.displayName) { environment.profile?.weeklyFrequency = option }
                    }
                }
            }
        }
    }

    // MARK: Emergency contact

    private var emergencyCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("EMERGENCY CONTACT")
                    .font(.bsCaption)
                    .tracking(1.2)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                // Big tap-to-pick button — no typing needed.
                Button {
                    showContactPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.bsBlack)
                        Text(environment.profile?.emergencyContact?.isEmpty == false
                             ? environment.profile!.emergencyContact!
                             : "Choose from Contacts")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.bsBlack)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .background(Color.bsPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                // Manual fallback / edit.
                labeledField("OR ENTER MANUALLY", placeholder: "Name & phone",
                             text: bindingFor(\.emergencyContact),
                             font: .bsBody, keyboard: .phonePad, autocap: .words)

                if environment.profile?.emergencyContact?.isEmpty == false {
                    Button(role: .destructive) {
                        environment.profile?.emergencyContact = nil
                    } label: {
                        Label("Clear contact", systemImage: "xmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.bsSevere)
                    }
                }

                Text("Texted automatically if the crash-SOS countdown isn't dismissed.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bsWhite.opacity(0.4))
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { name, phone in
                let combined = [name, phone].filter { !$0.isEmpty }.joined(separator: " · ")
                environment.profile?.emergencyContact = combined.isEmpty ? phone : combined
                showContactPicker = false
            }
            .ignoresSafeArea()
        }
    }

    // MARK: Account

    private var accountCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCOUNT")
                    .font(.bsCaption)
                    .tracking(1.2)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                if let email = environment.authService.currentEmail {
                    Text(email)
                        .font(.bsBody)
                        .foregroundStyle(Color.bsWhite.opacity(0.7))
                }

                Button(role: .destructive) {
                    // Persist edits, then sign out.
                    if let profile = environment.profile {
                        Task { try? await environment.saveProfile(profile) }
                    }
                    environment.signOut()
                } label: {
                    Text("Sign out")
                        .font(.bsBody)
                        .foregroundStyle(Color.bsSevere)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Reusable bits

    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        font: Font,
        keyboard: UIKeyboardType,
        autocap: TextInputAutocapitalization
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.bsCaption)
                .tracking(1.2)
                .foregroundStyle(Color.bsWhite.opacity(0.6))
            TextField("", text: text, prompt: Text(placeholder)
                .foregroundColor(Color.bsWhite.opacity(0.3)))
                .font(font)
                .foregroundStyle(Color.bsWhite)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(keyboard == .emailAddress)
        }
    }

    private func pickerRow<Content: View>(
        label: String,
        current: String,
        @ViewBuilder menu: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.bsCaption)
                .tracking(1.2)
                .foregroundStyle(Color.bsWhite.opacity(0.6))
            Spacer()
            Menu {
                menu()
            } label: {
                HStack(spacing: 6) {
                    Text(current)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.bsPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.bsPrimary)
                }
            }
        }
    }

    /// Bridge a `String?` field on the (optional) profile to a `Binding<String>`.
    private func bindingFor(_ keyPath: WritableKeyPath<Profile, String?>) -> Binding<String> {
        Binding(
            get: { environment.profile?[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                environment.profile?[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}

#Preview {
    ProfileView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
