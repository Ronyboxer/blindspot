//
//  OnboardingView.swift
//  Blind Spot
//
//  First-run onboarding. A short, editorial multi-step flow that collects the
//  rider's name, email, phone, skill level, and weekly riding frequency, then
//  hands off to the main app.
//
//  Visuals use the brand system: coral primary, Instrument Serif headings,
//  JetBrains Mono labels/buttons, dark surfaces.
//

import SwiftUI

struct OnboardingView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = OnboardingViewModel()

    // Focus management so each text step's field is ready to type into.
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            Color.bsBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress + back, hidden on the welcome screen.
                if !viewModel.isFirstStep {
                    header
                }

                // The current step's content.
                Group {
                    switch viewModel.step {
                    case .welcome:   welcomeStep
                    case .name:      textStep(
                        title: "What's your name?",
                        subtitle: "So we can personalize your rides.",
                        placeholder: "Your name",
                        text: $viewModel.name,
                        keyboard: .default,
                        textContentType: .name)
                    case .email:     textStep(
                        title: "Your email",
                        subtitle: "We'll use it for your account when sign-in arrives.",
                        placeholder: "you@example.com",
                        text: $viewModel.email,
                        keyboard: .emailAddress,
                        textContentType: .emailAddress)
                    case .phone:     textStep(
                        title: "Your phone number",
                        subtitle: "Used for ride alerts and crash SOS later.",
                        placeholder: "(555) 123-4567",
                        text: $viewModel.phone,
                        keyboard: .phonePad,
                        textContentType: .telephoneNumber)
                    case .skill:     skillStep
                    case .frequency: frequencyStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                if let error = viewModel.saveError {
                    Text(error)
                        .font(.bsCaption)
                        .foregroundStyle(Color.bsSevere)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        // Prefill name/email from the signed-in account.
        .onAppear { viewModel.prefill(from: environment.authService) }
        // Animate transitions between steps.
        .animation(.easeInOut(duration: 0.25), value: viewModel.step)
    }

    // MARK: - Header (progress + back)

    private var header: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.bsWhite)
            }

            // Slim progress bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.bsGraphite)
                    Capsule()
                        .fill(Color.bsPrimary)
                        .frame(width: geo.size.width * viewModel.progress)
                        .animation(.easeInOut, value: viewModel.progress)
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            // Wordmark-ish brand lockup.
            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(Color.bsPrimary)

            Text("Blind Spot")
                .font(.bsDisplay)
                .foregroundStyle(Color.bsWhite)

            Text("Crowd-sourced cycling safety. Map hazards, recap your rides, and ride with a crash SOS watching your back.")
                .font(.bsBody)
                .foregroundStyle(Color.bsWhite.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    // MARK: - Text steps (name / email / phone)

    private func textStep(
        title: String,
        subtitle: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        textContentType: UITextContentType?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(title, subtitle: subtitle)

            TextField("", text: text, prompt: Text(placeholder)
                .foregroundColor(Color.bsWhite.opacity(0.3)))
                .font(.bsHeadline)
                .foregroundStyle(Color.bsWhite)
                .keyboardType(keyboard)
                .textContentType(textContentType)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .focused($fieldFocused)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.bsGraphite)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.bsPrimary.opacity(fieldFocused ? 0.8 : 0), lineWidth: 2)
                )

            Spacer()
        }
        .padding(.top, 8)
        // Auto-focus the field when a text step appears.
        .onAppear { fieldFocused = true }
    }

    // MARK: - Skill step

    private var skillStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("How would you rate your riding?",
                      subtitle: "Helps us tune hazard alerts to your comfort level.")

            ForEach(BikingSkill.allCases) { option in
                OptionRow(
                    symbol: option.symbolName,
                    title: option.displayName,
                    subtitle: option.blurb,
                    isSelected: viewModel.skill == option
                ) {
                    viewModel.skill = option
                }
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Frequency step

    private var frequencyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("How often do you bike?",
                      subtitle: "A typical week.")

            ForEach(RideFrequency.allCases) { option in
                OptionRow(
                    symbol: option.symbolName,
                    title: option.displayName,
                    subtitle: nil,
                    isSelected: viewModel.frequency == option
                ) {
                    viewModel.frequency = option
                }
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Shared pieces

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.bsTitle)
                .foregroundStyle(Color.bsWhite)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.bsBody)
                .foregroundStyle(Color.bsWhite.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerTitle: String {
        if viewModel.isLastStep { return viewModel.isSaving ? "SAVING…" : "GET STARTED" }
        return viewModel.isFirstStep ? "GET STARTED" : "CONTINUE"
    }

    private var footer: some View {
        PrimaryButton(title: footerTitle) {
            // Dismiss the keyboard before moving on.
            fieldFocused = false
            if viewModel.isLastStep {
                Task { await viewModel.finish(into: environment) }
            } else {
                viewModel.advance()
            }
        }
        // Dim + disable until the current step is valid (and while saving).
        .opacity(viewModel.canAdvance && !viewModel.isSaving ? 1 : 0.4)
        .disabled(!viewModel.canAdvance || viewModel.isSaving)
    }
}

// MARK: - Option row (selectable card for skill / frequency)

private struct OptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isSelected ? Color.bsBlack : Color.bsPrimary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.bsBlack : Color.bsWhite)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Color.bsBlack.opacity(0.7)
                                                        : Color.bsWhite.opacity(0.5))
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.bsBlack)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selected rows fill with coral; unselected stay graphite.
            .background(isSelected ? Color.bsPrimary : Color.bsGraphite)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
