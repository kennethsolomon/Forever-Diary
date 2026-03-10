import Foundation
import CryptoKit

final class APIClient {
    private let authService: CognitoAuthService

    init(authService: CognitoAuthService) {
        self.authService = authService
    }

    /// POST JSON to API Gateway with IAM auth.
    func post(path: String, body: [String: Any]) async throws -> [String: Any] {
        try await authService.refreshIfNeeded()
        guard let creds = authService.credentials else {
            throw APIError.notAuthenticated
        }

        let urlString = "\(AWSConfig.apiGatewayURL)\(path)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        try signRequest(&request, credentials: creds)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }

    /// GET from API Gateway with IAM auth and query parameters.
    func get(path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        try await authService.refreshIfNeeded()
        guard let creds = authService.credentials else {
            throw APIError.notAuthenticated
        }

        var components = URLComponents(string: "\(AWSConfig.apiGatewayURL)\(path)")
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        try signRequest(&request, credentials: creds)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "unknown"
            throw APIError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }
        return json
    }

    /// Upload data to a presigned S3 URL.
    func uploadToPresignedURL(_ urlString: String, data: Data, contentType: String = "image/jpeg") async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.uploadFailed
        }
    }

    /// Download data from a presigned S3 URL.
    func downloadFromPresignedURL(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.downloadFailed
        }
        return data
    }

    // MARK: - AWS SigV4 Signing

    private func signRequest(_ request: inout URLRequest, credentials: CognitoAuthService.AWSCredentials) throws {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now)

        let shortDateFormatter = DateFormatter()
        shortDateFormatter.dateFormat = "yyyyMMdd"
        shortDateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStamp = shortDateFormatter.string(from: now)

        let service = "execute-api"
        let region = AWSConfig.region

        guard let url = request.url,
              let host = url.host else {
            throw APIError.invalidURL
        }

        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(credentials.sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")

        let method = request.httpMethod ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query ?? ""

        // Canonical query string (sorted)
        let canonicalQueryString: String
        if query.isEmpty {
            canonicalQueryString = ""
        } else {
            let pairs = query.components(separatedBy: "&").sorted()
            canonicalQueryString = pairs.joined(separator: "&")
        }

        let bodyData = request.httpBody ?? Data()
        let bodyHash = Data(SHA256.hash(data: bodyData)).hexString

        let signedHeaders = "content-type;host;x-amz-date;x-amz-security-token"
        let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""

        let canonicalRequest = [
            method,
            path,
            canonicalQueryString,
            "content-type:\(contentType)\n",
            "host:\(host)\n",
            "x-amz-date:\(amzDate)\n",
            "x-amz-security-token:\(credentials.sessionToken)\n",
            "",
            signedHeaders,
            bodyHash
        ].joined(separator: "\n")

        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let canonicalRequestHash = Data(SHA256.hash(data: Data(canonicalRequest.utf8))).hexString

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // Derive signing key
        let kDate = hmacSHA256(key: Data("AWS4\(credentials.secretKey)".utf8), data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))

        let signature = hmacSHA256(key: kSigning, data: Data(stringToSign.utf8)).hexString

        let authorization = "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    private func hmacSHA256(key: Data, data: Data) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    enum APIError: Error, LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, body: String)
        case uploadFailed
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Not authenticated"
            case .invalidURL: return "Invalid URL"
            case .invalidResponse: return "Invalid response"
            case .httpError(let code, let body): return "HTTP \(code): \(body)"
            case .uploadFailed: return "Upload failed"
            case .downloadFailed: return "Download failed"
            }
        }
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
