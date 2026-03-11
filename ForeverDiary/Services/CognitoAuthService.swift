import Foundation

@Observable
final class CognitoAuthService {
    private(set) var identityId: String?
    private(set) var credentials: AWSCredentials?
    private(set) var isAuthenticated = false
    private(set) var userEmail: String?

    private let keychainIdentityKey = "cognitoIdentityId"
    private let keychainEmailKey = "cognitoUserEmail"
    private let keychainIdTokenKey = "cognitoIdToken"
    private let keychainRefreshKey = "cognitoRefreshToken"
    private let keychainGoogleIdTokenKey = "googleIdToken"
    private let keychainGoogleRefreshKey = "googleRefreshToken"

    private let identityEndpoint = "https://cognito-identity.\(AWSConfig.region).amazonaws.com"
    private let userPoolEndpoint = "https://cognito-idp.\(AWSConfig.region).amazonaws.com/"

    private var idToken: String?
    private var refreshToken: String?
    private var googleIdToken: String?
    private var googleRefreshToken: String?

    struct AWSCredentials {
        let accessKeyId: String
        let secretKey: String
        let sessionToken: String
        let expiration: Date
    }

    init() {
        identityId = KeychainHelper.load(key: keychainIdentityKey)
        userEmail = KeychainHelper.load(key: keychainEmailKey)
        idToken = KeychainHelper.load(key: keychainIdTokenKey)
        refreshToken = KeychainHelper.load(key: keychainRefreshKey)
        googleIdToken = KeychainHelper.load(key: keychainGoogleIdTokenKey)
        googleRefreshToken = KeychainHelper.load(key: keychainGoogleRefreshKey)
        if identityId != nil, userEmail != nil {
            isAuthenticated = true
        }
    }

    // MARK: - User Pool Auth

    /// Register a new account. The user must confirm their email before signing in.
    func signUp(email: String, password: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.cognitoUserPoolClientId,
            "Username": email,
            "Password": password
        ]
        _ = try await userPoolRequest(target: "AWSCognitoIdentityProviderService.SignUp", body: body)
    }

    /// Confirm registration with the 6-digit code sent to the user's email.
    func confirmSignUp(email: String, code: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.cognitoUserPoolClientId,
            "Username": email,
            "ConfirmationCode": code
        ]
        _ = try await userPoolRequest(target: "AWSCognitoIdentityProviderService.ConfirmSignUp", body: body)
    }

    /// Sign in with email and password. Obtains Cognito credentials on success.
    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = [
            "AuthFlow": "USER_PASSWORD_AUTH",
            "AuthParameters": [
                "USERNAME": email,
                "PASSWORD": password
            ],
            "ClientId": AWSConfig.cognitoUserPoolClientId
        ]
        let data = try await userPoolRequest(
            target: "AWSCognitoIdentityProviderService.InitiateAuth",
            body: body
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authResult = json["AuthenticationResult"] as? [String: Any],
              let newIdToken = authResult["IdToken"] as? String,
              let newRefreshToken = authResult["RefreshToken"] as? String else {
            throw CognitoError.invalidResponse
        }

        idToken = newIdToken
        refreshToken = newRefreshToken

        let logins = userPoolLogins(idToken: newIdToken)
        let id = try await getOrCreateIdentity(logins: logins)
        let creds = try await getCredentials(identityId: id, logins: logins)

        identityId = id
        credentials = creds
        userEmail = email
        isAuthenticated = true

        KeychainHelper.save(key: keychainIdentityKey, value: id)
        KeychainHelper.save(key: keychainEmailKey, value: email)
        KeychainHelper.save(key: keychainIdTokenKey, value: newIdToken)
        KeychainHelper.save(key: keychainRefreshKey, value: newRefreshToken)
    }

    /// Send a password-reset code to the given email.
    func forgotPassword(email: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.cognitoUserPoolClientId,
            "Username": email
        ]
        _ = try await userPoolRequest(target: "AWSCognitoIdentityProviderService.ForgotPassword", body: body)
    }

    /// Confirm password reset with the code and a new password.
    func confirmNewPassword(email: String, code: String, newPassword: String) async throws {
        let body: [String: Any] = [
            "ClientId": AWSConfig.cognitoUserPoolClientId,
            "Username": email,
            "ConfirmationCode": code,
            "Password": newPassword
        ]
        _ = try await userPoolRequest(
            target: "AWSCognitoIdentityProviderService.ConfirmForgotPassword",
            body: body
        )
    }

    /// Sign in with a Google ID token. Federates via Cognito Identity Pool.
    func signInWithGoogle(idToken: String, refreshToken: String?, email: String?) async throws {
        let logins = ["accounts.google.com": idToken]
        let id = try await getOrCreateIdentity(logins: logins)
        let creds = try await getCredentials(identityId: id, logins: logins)

        identityId = id
        credentials = creds
        userEmail = email
        googleIdToken = idToken
        googleRefreshToken = refreshToken
        isAuthenticated = true

        KeychainHelper.save(key: keychainIdentityKey, value: id)
        if let email { KeychainHelper.save(key: keychainEmailKey, value: email) }
        KeychainHelper.save(key: keychainGoogleIdTokenKey, value: idToken)
        if let refreshToken { KeychainHelper.save(key: keychainGoogleRefreshKey, value: refreshToken) }
    }

    /// Sign out: clear all credentials and Keychain state.
    func signOut() {
        identityId = nil
        credentials = nil
        idToken = nil
        refreshToken = nil
        googleIdToken = nil
        googleRefreshToken = nil
        userEmail = nil
        isAuthenticated = false
        KeychainHelper.delete(key: keychainIdentityKey)
        KeychainHelper.delete(key: keychainEmailKey)
        KeychainHelper.delete(key: keychainIdTokenKey)
        KeychainHelper.delete(key: keychainRefreshKey)
        KeychainHelper.delete(key: keychainGoogleIdTokenKey)
        KeychainHelper.delete(key: keychainGoogleRefreshKey)
    }

    /// Refresh AWS credentials if expired or about to expire (within 5 min).
    func refreshIfNeeded() async throws {
        guard let id = identityId else { return }
        if let creds = credentials, creds.expiration.timeIntervalSinceNow > 300 { return }

        // Cognito User Pool path: use refresh token to get new ID token
        if let rt = refreshToken {
            let body: [String: Any] = [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "AuthParameters": ["REFRESH_TOKEN": rt],
                "ClientId": AWSConfig.cognitoUserPoolClientId
            ]
            if let data = try? await userPoolRequest(
                target: "AWSCognitoIdentityProviderService.InitiateAuth",
                body: body
            ),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let authResult = json["AuthenticationResult"] as? [String: Any],
               let newIdToken = authResult["IdToken"] as? String {
                idToken = newIdToken
                KeychainHelper.save(key: keychainIdTokenKey, value: newIdToken)
                let logins = userPoolLogins(idToken: newIdToken)
                credentials = try await getCredentials(identityId: id, logins: logins)
                return
            }
        }

        // Google Sign-In path: use Google refresh token to get new Google ID token
        if let googleRT = googleRefreshToken {
            if let newGoogleIdToken = try? await refreshGoogleIdToken(refreshToken: googleRT) {
                googleIdToken = newGoogleIdToken
                KeychainHelper.save(key: keychainGoogleIdTokenKey, value: newGoogleIdToken)
                let logins = ["accounts.google.com": newGoogleIdToken]
                credentials = try await getCredentials(identityId: id, logins: logins)
                return
            }
        }

        // Last resort: try existing cached tokens
        if let token = idToken {
            let logins = userPoolLogins(idToken: token)
            if let creds = try? await getCredentials(identityId: id, logins: logins) {
                credentials = creds
                return
            }
        }
        if let token = googleIdToken {
            let logins = ["accounts.google.com": token]
            if let creds = try? await getCredentials(identityId: id, logins: logins) {
                credentials = creds
                return
            }
        }

        // All refresh paths failed — sign out
        signOut()
    }

    private func refreshGoogleIdToken(refreshToken: String) async throws -> String {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw CognitoError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let params = [
            "client_id=\(AWSConfig.googleClientId)",
            "refresh_token=\(refreshToken)",
            "grant_type=refresh_token"
        ].joined(separator: "&")
        request.httpBody = params.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newIdToken = json["id_token"] as? String else {
            throw CognitoError.requestFailed
        }
        return newIdToken
    }

    // MARK: - Cognito Identity REST API

    private func userPoolLogins(idToken: String) -> [String: String] {
        ["cognito-idp.\(AWSConfig.region).amazonaws.com/\(AWSConfig.cognitoUserPoolId)": idToken]
    }

    private func getOrCreateIdentity(logins: [String: String]) async throws -> String {
        let body: [String: Any] = [
            "IdentityPoolId": AWSConfig.cognitoIdentityPoolId,
            "Logins": logins
        ]
        let data = try await cognitoIdentityRequest(target: "AWSCognitoIdentityService.GetId", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["IdentityId"] as? String else {
            throw CognitoError.invalidResponse
        }
        return id
    }

    private func getCredentials(identityId: String, logins: [String: String]) async throws -> AWSCredentials {
        let body: [String: Any] = [
            "IdentityId": identityId,
            "Logins": logins
        ]
        let data = try await cognitoIdentityRequest(
            target: "AWSCognitoIdentityService.GetCredentialsForIdentity",
            body: body
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let creds = json["Credentials"] as? [String: Any],
              let accessKeyId = creds["AccessKeyId"] as? String,
              let secretKey = creds["SecretKey"] as? String,
              let sessionToken = creds["SessionToken"] as? String,
              let expiration = creds["Expiration"] as? Double else {
            throw CognitoError.invalidResponse
        }
        return AWSCredentials(
            accessKeyId: accessKeyId,
            secretKey: secretKey,
            sessionToken: sessionToken,
            expiration: Date(timeIntervalSince1970: expiration)
        )
    }

    private func userPoolRequest(target: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: userPoolEndpoint) else { throw CognitoError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw CognitoError.serverError(message)
            }
            throw CognitoError.requestFailed
        }
        return data
    }

    private func cognitoIdentityRequest(target: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: identityEndpoint) else { throw CognitoError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw CognitoError.serverError(message)
            }
            throw CognitoError.requestFailed
        }
        return data
    }

    enum CognitoError: Error, LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .serverError(let msg): return msg
            case .requestFailed: return "Request failed. Please check your connection."
            case .invalidResponse: return "Unexpected response from server."
            case .invalidURL: return "Invalid server URL."
            }
        }
    }
}
