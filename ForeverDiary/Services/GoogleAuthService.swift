import Foundation
import AuthenticationServices
import CryptoKit

@Observable
final class GoogleAuthService: NSObject {

    struct GoogleCredential {
        let idToken: String
        let email: String?
    }

    private var webAuthSession: ASWebAuthenticationSession?

    @MainActor
    func signIn() async throws -> GoogleCredential {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let redirectURI = "\(AWSConfig.googleReversedClientId):/oauth2callback"

        guard var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth") else {
            throw GoogleAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AWSConfig.googleClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components.url else { throw GoogleAuthError.invalidURL }

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: AWSConfig.googleReversedClientId
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleAuthError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      let comps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GoogleAuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthSession = session
            if !session.start() {
                continuation.resume(throwing: GoogleAuthError.sessionFailed)
            }
        }

        return try await exchangeCode(code: code, codeVerifier: codeVerifier, redirectURI: redirectURI)
    }

    private func exchangeCode(code: String, codeVerifier: String, redirectURI: String) async throws -> GoogleCredential {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleAuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let params: [String: String] = [
            "code": code,
            "client_id": AWSConfig.googleClientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": codeVerifier
        ]
        // RFC 3986 unreserved chars only — correct for application/x-www-form-urlencoded
        let formAllowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String else {
            throw GoogleAuthError.tokenExchangeFailed
        }

        let email = jwtClaim("email", from: idToken)
        return GoogleCredential(idToken: idToken, email: email)
    }

    // MARK: - Helpers

    /// Reads a claim from a JWT payload for display purposes only.
    /// The signature is NOT verified here — Cognito validates the full token server-side before issuing credentials.
    private func jwtClaim(_ claim: String, from token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[claim] as? String
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    enum GoogleAuthError: Error, LocalizedError {
        case invalidURL, cancelled, invalidCallback, tokenExchangeFailed, sessionFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid Google auth URL."
            case .cancelled: return nil
            case .invalidCallback: return "Invalid response from Google."
            case .tokenExchangeFailed: return "Failed to complete Google sign-in."
            case .sessionFailed: return "Could not start Google sign-in session."
            }
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
