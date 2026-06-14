//
//  SignInView.swift
//  Blind Spot
//
//  The sign-in / create-account screen (Firebase email + Google). Shown by
//  RootView whenever no user is signed in.
//

import SwiftUI

struct SignInView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = SignInViewModel()
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        ZStack {
            Color.bsBlack.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                // Brand lockup.
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color.bsPrimary)
                Text("Blind Spot")
                    .font(.bsDisplay)
                    .foregroundStyle(Color.bsWhite)
                Text(viewModel.mode == .signIn ? "Welcome back." : "Create your account.")
                    .font(.bsBody)
                    .foregroundStyle(Color.bsWhite.opacity(0.6))

                // Fields.
                VStack(spacing: 12) {
                    field("Email", text: $viewModel.email, field: .email,
                          keyboard: .emailAddress, secure: false)
                    field("Password", text: $viewModel.password, field: .password,
                          keyboard: .default, secure: true)
                }
                .padding(.top, 8)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.bsCaption)
                        .foregroundStyle(Color.bsSevere)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Primary submit (email/password).
                PrimaryButton(title: viewModel.submitTitle) {
                    focus = nil
                    Task { await viewModel.submit(using: environment.authService) }
                }
                .opacity(viewModel.canSubmit ? 1 : 0.4)
                .disabled(!viewModel.canSubmit)
                .padding(.top, 4)

                // Divider + Google.
                HStack {
                    line; Text("or").font(.bsCaption).foregroundStyle(Color.bsWhite.opacity(0.4)); line
                }
                googleButton

                // Toggle sign in / sign up.
                Button(viewModel.togglePrompt) { viewModel.toggleMode() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.bsPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)

                Spacer()
            }
            .padding(.horizontal, 24)

            if viewModel.isWorking {
                ProgressView().tint(.bsPrimary)
            }
        }
    }

    // MARK: Pieces

    private var line: some View {
        Rectangle().fill(Color.bsWhite.opacity(0.15)).frame(height: 1)
    }

    private func field(_ placeholder: String, text: Binding<String>, field: Field,
                       keyboard: UIKeyboardType, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: prompt(placeholder))
            } else {
                TextField("", text: text, prompt: prompt(placeholder))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.bsBody)
        .foregroundStyle(Color.bsWhite)
        .focused($focus, equals: field)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color.bsGraphite)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func prompt(_ s: String) -> Text {
        Text(s).foregroundColor(Color.bsWhite.opacity(0.3))
    }

    private var googleButton: some View {
        Button {
            Task { await viewModel.signInWithGoogle(using: environment.authService) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 17, weight: .bold))
                Text("CONTINUE WITH GOOGLE")
                    .font(.bsButton)
            }
            .foregroundStyle(Color.bsWhite)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.bsGraphite)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.bsWhite.opacity(0.15), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment.preview)
        .preferredColorScheme(.dark)
}
