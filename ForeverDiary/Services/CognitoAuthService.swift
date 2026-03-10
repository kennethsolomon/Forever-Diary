import Foundation

@Observable
final class CognitoAuthService {
    private(set) var identityId: String?
    private(set) var credentials: AWSCredentials?
    private(set) var isAuthenticated = false

    private let keychainKey = "cognitoIdentityId"
    private let endpoint = "https://cognito-identity.\(AWSConfig.region).amazonaws.com"

    struct AWSCredentials {
        let accessKeyId: String
        let secretKey: String
        let sessionToken: String
        let expiration: Date
    }

    init() {
        // Restore identity from Keychain
        identityId = KeychainHelper.load(key: keychainKey)
    }

    /// Authenticate anonymously via Cognito. Returns the identity ID.
    func authenticate() async throws -> String {
        let id = try await getOrCreateIdentity()
        let creds = try await getCredentials(identityId: id)

        identityId = id
        credentials = creds
        isAuthenticated = true

        // Persist identity in Keychain (survives reinstall)
        KeychainHelper.save(key: keychainKey, value: id)

        return id
    }

    /// Refresh credentials if expired or about to expire (within 5 min).
    func refreshIfNeeded() async throws {
        guard let id = identityId else {
            _ = try await authenticate()
            return
        }

        if let creds = credentials, creds.expiration.timeIntervalSinceNow > 300 {
            return // Still valid for >5 min
        }

        let creds = try await getCredentials(identityId: id)
        credentials = creds
    }

    // MARK: - Cognito REST API

    private func getOrCreateIdentity() async throws -> String {
        // If we have a stored identity, return it. Credentials are fetched separately.
        if let stored = identityId {
            return stored
        }

        // Call Cognito GetId
        let body: [String: Any] = [
            "IdentityPoolId": AWSConfig.cognitoIdentityPoolId
        ]

        let data = try await cognitoRequest(target: "AWSCognitoIdentityService.GetId", body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["IdentityId"] as? String else {
            throw CognitoError.invalidResponse
        }
        return id
    }

    private func getCredentials(identityId: String) async throws -> AWSCredentials {
        let body: [String: Any] = [
            "IdentityId": identityId
        ]

        let data = try await cognitoRequest(target: "AWSCognitoIdentityService.GetCredentialsForIdentity", body: body)
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

    private func cognitoRequest(target: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw CognitoError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue(target, forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CognitoError.requestFailed
        }
        return data
    }

    enum CognitoError: Error {
        case invalidURL
        case invalidResponse
        case requestFailed
    }
}
