import SwiftUI

private enum AuthScreen {
    case signIn
    case createAccount
    case verify(email: String, password: String)
    case forgotPassword
    case resetPassword(email: String)
}

struct SignInView: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(GoogleAuthService.self) private var googleAuth

    @State private var screen: AuthScreen = .signIn
    @State private var dotsVisible = false
    @State private var titleVisible = false
    @State private var formVisible = false

    var body: some View {
        ZStack {
            Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                dotRing
                    .opacity(dotsVisible ? 1 : 0)
                    .padding(.bottom, 32)

                VStack(spacing: 8) {
                    Text("Forever Diary")
                        .font(.system(.largeTitle, design: .serif, weight: .light))
                        .foregroundStyle(Color("textPrimary"))
                        .offset(y: titleVisible ? 0 : 20)
                        .opacity(titleVisible ? 1 : 0)

                    Text("Every day, a story.\nEvery year, a life.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                        .multilineTextAlignment(.center)
                        .opacity(titleVisible ? 1 : 0)
                }

                Spacer()

                screenContent
                    .opacity(formVisible ? 1 : 0)
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) { dotsVisible = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { titleVisible = true }
            withAnimation(.easeIn(duration: 0.4).delay(0.5)) { formVisible = true }
        }
    }

    @ViewBuilder
    private var screenContent: some View {
        switch screen {
        case .signIn:
            SignInForm(
                onCreateAccount: { screen = .createAccount },
                onForgotPassword: { screen = .forgotPassword }
            )
        case .createAccount:
            CreateAccountForm(
                onSignIn: { screen = .signIn },
                onVerify: { email, password in screen = .verify(email: email, password: password) }
            )
        case .verify(let email, let password):
            VerifyForm(
                email: email,
                password: password,
                onBack: { screen = .createAccount }
            )
        case .forgotPassword:
            ForgotPasswordForm(
                onBack: { screen = .signIn },
                onReset: { email in screen = .resetPassword(email: email) }
            )
        case .resetPassword(let email):
            ResetPasswordForm(
                email: email,
                onBack: { screen = .forgotPassword },
                onDone: { screen = .signIn }
            )
        }
    }

    private var dotRing: some View {
        let count = 14
        let radius: CGFloat = 80
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Circle()
                    .fill(Color("accentBright"))
                    .frame(width: 5, height: 5)
                    .offset(
                        x: radius * CGFloat(cos(angle)),
                        y: radius * CGFloat(sin(angle))
                    )
                    .opacity(0.10 + 0.06 * Double(i % 3))
            }
        }
        .frame(width: radius * 2 + 10, height: radius * 2 + 10)
    }
}

// MARK: - Sign In Form

private struct SignInForm: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(GoogleAuthService.self) private var googleAuth
    let onCreateAccount: () -> Void
    let onForgotPassword: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                AuthTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                AuthSecureField(placeholder: "Password", text: $password)
            }
            .padding(.horizontal, 40)

            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await signIn() }
            } label: {
                if isLoading {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    Text("Sign In")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color("accentBright"))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .disabled(isLoading || email.isEmpty || password.isEmpty)

            Button(action: onForgotPassword) {
                Text("Forgot password?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                Button(action: onCreateAccount) {
                    Text("Create one")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color("accentBright"))
                }
            }

            GoogleSignInDivider()

            GoogleSignInButton(isLoading: isLoading) {
                Task { await signInWithGoogle() }
            }
            .padding(.horizontal, 40)
        }
    }

    private func signIn() async {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            try await cognitoAuth.signIn(
                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                password: password
            )
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signInWithGoogle() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let credential = try await googleAuth.signIn()
            try await cognitoAuth.signInWithGoogle(idToken: credential.idToken, email: credential.email)
        } catch let error as GoogleAuthService.GoogleAuthError where error == .cancelled {
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Create Account Form

private struct CreateAccountForm: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(GoogleAuthService.self) private var googleAuth
    let onSignIn: () -> Void
    let onVerify: (String, String) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && password != confirmPassword
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                AuthTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                AuthSecureField(placeholder: "Password (min 8 characters)", text: $password)
                AuthSecureField(placeholder: "Confirm password", text: $confirmPassword)
            }
            .padding(.horizontal, 40)

            if passwordMismatch {
                Text("Passwords don't match")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await createAccount() }
            } label: {
                if isLoading {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    Text("Create Account")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color("accentBright"))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .disabled(isLoading || email.isEmpty || password.count < 8 || passwordMismatch || confirmPassword.isEmpty)

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                Button(action: onSignIn) {
                    Text("Sign in")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color("accentBright"))
                }
            }

            GoogleSignInDivider()

            GoogleSignInButton(isLoading: isLoading) {
                Task { await signInWithGoogle() }
            }
            .padding(.horizontal, 40)
        }
    }

    private func createAccount() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmedEmail.isEmpty, password.count >= 8, password == confirmPassword else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            try await cognitoAuth.signUp(email: trimmedEmail, password: password)
            await MainActor.run { onVerify(trimmedEmail, password) }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signInWithGoogle() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let credential = try await googleAuth.signIn()
            try await cognitoAuth.signInWithGoogle(idToken: credential.idToken, email: credential.email)
        } catch let error as GoogleAuthService.GoogleAuthError where error == .cancelled {
            await MainActor.run { isLoading = false }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Verify Form

private struct VerifyForm: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    let email: String
    let password: String
    let onBack: () -> Void

    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Check your email")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))
                Text("Enter the 6-digit code sent to\n\(email)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
                    .multilineTextAlignment(.center)
            }

            AuthTextField(placeholder: "Verification code", text: $code, keyboardType: .numberPad)
                .padding(.horizontal, 40)

            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await verify() }
            } label: {
                if isLoading {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    Text("Verify")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color("accentBright"))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .disabled(isLoading || code.count < 6)

            Button(action: onBack) {
                Text("Back")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        }
    }

    private func verify() async {
        guard code.count >= 6 else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            try await cognitoAuth.confirmSignUp(email: email, code: code.trimmingCharacters(in: .whitespaces))
            try await cognitoAuth.signIn(email: email, password: password)
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Forgot Password Form

private struct ForgotPasswordForm: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    let onBack: () -> Void
    let onReset: (String) -> Void

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Reset your password")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))
                Text("We'll send a reset code to your email.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            AuthTextField(placeholder: "Email", text: $email, keyboardType: .emailAddress)
                .padding(.horizontal, 40)

            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await sendCode() }
            } label: {
                if isLoading {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    Text("Send Reset Code")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color("accentBright"))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .disabled(isLoading || email.isEmpty)

            Button(action: onBack) {
                Text("Back to Sign In")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        }
    }

    private func sendCode() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            try await cognitoAuth.forgotPassword(email: trimmed)
            await MainActor.run { onReset(trimmed) }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Reset Password Form

private struct ResetPasswordForm: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    let email: String
    let onBack: () -> Void
    let onDone: () -> Void

    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Enter new password")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Color("textPrimary"))
                Text("Use the code sent to \(email)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }

            VStack(spacing: 10) {
                AuthTextField(placeholder: "Reset code", text: $code, keyboardType: .numberPad)
                AuthSecureField(placeholder: "New password (min 8 characters)", text: $newPassword)
                AuthSecureField(placeholder: "Confirm new password", text: $confirmPassword)
            }
            .padding(.horizontal, 40)

            if passwordMismatch {
                Text("Passwords don't match")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await resetPassword() }
            } label: {
                if isLoading {
                    ProgressView().tint(.black).frame(maxWidth: .infinity).frame(height: 50)
                } else {
                    Text("Reset Password")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
            }
            .background(Color("accentBright"))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .disabled(isLoading || code.isEmpty || newPassword.count < 8 || passwordMismatch || confirmPassword.isEmpty)

            Button(action: onBack) {
                Text("Back")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color("textSecondary"))
            }
        }
    }

    private func resetPassword() async {
        guard !code.isEmpty, newPassword.count >= 8, newPassword == confirmPassword else { return }
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            try await cognitoAuth.confirmNewPassword(
                email: email,
                code: code.trimmingCharacters(in: .whitespaces),
                newPassword: newPassword
            )
            await MainActor.run { onDone() }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Google Sign-In Components

private struct GoogleSignInDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
            Text("or")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color("textSecondary"))
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 40)
    }
}

private struct GoogleSignInButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(Color(red: 0.2, green: 0.2, blue: 0.2))
                } else {
                    Text("G")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    Text("Continue with Google")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .background(Color.white)
        .cornerRadius(12)
        .disabled(isLoading)
    }
}

// MARK: - Shared Field Components

private struct AuthTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Color("textPrimary"))
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

private struct AuthSecureField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Color("textPrimary"))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}
