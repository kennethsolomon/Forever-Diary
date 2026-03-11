import SwiftUI

struct SignInMacView: View {
    @Environment(CognitoAuthService.self) private var cognitoAuth
    @Environment(GoogleAuthService.self) private var googleAuth

    enum AuthScreen { case signIn, createAccount, verify(email: String), forgotPassword, resetPassword(email: String) }

    @State private var screen: AuthScreen = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var verifyCode = ""
    @State private var resetCode = ""
    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Forever Diary")
                        .font(.system(.title, design: .rounded, weight: .bold))
                }

                switch screen {
                case .signIn: signInForm
                case .createAccount: createAccountForm
                case .verify(let e): verifyForm(email: e)
                case .forgotPassword: forgotPasswordForm
                case .resetPassword(let e): resetPasswordForm(email: e)
                }
            }
            .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var signInForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).font(.caption)
            }

            Button(action: doSignIn) {
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("Sign In").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Divider()

            Button(action: doGoogleSignIn) {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Sign in with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isLoading)

            HStack {
                Button("Create Account") { screen = .createAccount }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button("Forgot Password?") { screen = .forgotPassword }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var createAccountForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            SecureField("Confirm Password", text: $confirmPassword).textFieldStyle(.roundedBorder)

            if let err = errorMessage { Text(err).foregroundStyle(.red).font(.caption) }

            Button(action: doCreateAccount) {
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("Create Account").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Back to Sign In") { screen = .signIn }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func verifyForm(email: String) -> some View {
        VStack(spacing: 12) {
            Text("Check your email for a verification code.").font(.caption).foregroundStyle(.secondary)
            TextField("Verification Code", text: $verifyCode).textFieldStyle(.roundedBorder)

            if let err = errorMessage { Text(err).foregroundStyle(.red).font(.caption) }

            Button(action: { doVerify(email: email) }) {
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("Verify").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Back to Sign In") { screen = .signIn }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
        }
    }

    private var forgotPasswordForm: some View {
        VStack(spacing: 12) {
            TextField("Email", text: $email).textFieldStyle(.roundedBorder)

            if let err = errorMessage { Text(err).foregroundStyle(.red).font(.caption) }

            Button(action: doForgotPassword) {
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("Send Reset Code").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)

            Button("Back to Sign In") { screen = .signIn }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func resetPasswordForm(email: String) -> some View {
        VStack(spacing: 12) {
            TextField("Reset Code", text: $resetCode).textFieldStyle(.roundedBorder)
            SecureField("New Password", text: $newPassword).textFieldStyle(.roundedBorder)

            if let err = errorMessage { Text(err).foregroundStyle(.red).font(.caption) }

            Button(action: { doResetPassword(email: email) }) {
                if isLoading { ProgressView().controlSize(.small) }
                else { Text("Reset Password").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
    }

    // MARK: - Actions

    private func doSignIn() {
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await cognitoAuth.signIn(email: email, password: password)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func doGoogleSignIn() {
        isLoading = true; errorMessage = nil
        Task {
            do {
                let cred = try await googleAuth.signIn()
                try await cognitoAuth.signInWithGoogle(idToken: cred.idToken, refreshToken: cred.refreshToken, email: cred.email)
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func doCreateAccount() {
        guard password == confirmPassword else { errorMessage = "Passwords do not match."; return }
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await cognitoAuth.signUp(email: email, password: password)
                await MainActor.run { screen = .verify(email: email) }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func doVerify(email: String) {
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await cognitoAuth.confirmSignUp(email: email, code: verifyCode)
                await MainActor.run { screen = .signIn }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func doForgotPassword() {
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await cognitoAuth.forgotPassword(email: email)
                await MainActor.run { screen = .resetPassword(email: email) }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }

    private func doResetPassword(email: String) {
        isLoading = true; errorMessage = nil
        Task {
            do {
                try await cognitoAuth.confirmNewPassword(email: email, code: resetCode, newPassword: newPassword)
                await MainActor.run { screen = .signIn }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run { isLoading = false }
        }
    }
}
