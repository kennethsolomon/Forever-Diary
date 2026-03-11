import XCTest
import SwiftData
import CryptoKit
@testable import ForeverDiary

final class CloudSyncServiceTests: XCTestCase {

    // MARK: - CognitoAuthService init state

    func testCognitoAuthServiceInitialState() {
        let service = CognitoAuthService()
        XCTAssertFalse(service.isAuthenticated)
        XCTAssertNil(service.credentials)
        // identityId may be nil or restored from Keychain
    }

    // MARK: - CognitoError cases

    func testCognitoErrorCases() {
        let invalidURL = CognitoAuthService.CognitoError.invalidURL
        let invalidResponse = CognitoAuthService.CognitoError.invalidResponse
        let requestFailed = CognitoAuthService.CognitoError.requestFailed

        // Verify they are distinct error cases
        XCTAssertFalse("\(invalidURL)" == "\(invalidResponse)")
        XCTAssertFalse("\(invalidResponse)" == "\(requestFailed)")
        XCTAssertFalse("\(invalidURL)" == "\(requestFailed)")
    }

    // MARK: - APIClient.APIError descriptions

    func testAPIErrorNotAuthenticated() {
        let error = APIClient.APIError.notAuthenticated
        XCTAssertEqual(error.errorDescription, "Not authenticated")
    }

    func testAPIErrorInvalidURL() {
        let error = APIClient.APIError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid URL")
    }

    func testAPIErrorInvalidResponse() {
        let error = APIClient.APIError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response")
    }

    func testAPIErrorHTTPError() {
        let error = APIClient.APIError.httpError(statusCode: 403, body: "Forbidden")
        XCTAssertEqual(error.errorDescription, "HTTP 403: Forbidden")
    }

    func testAPIErrorUploadFailed() {
        let error = APIClient.APIError.uploadFailed
        XCTAssertEqual(error.errorDescription, "Upload failed")
    }

    func testAPIErrorDownloadFailed() {
        let error = APIClient.APIError.downloadFailed
        XCTAssertEqual(error.errorDescription, "Download failed")
    }

    // MARK: - Data.hexString extension

    func testDataHexStringEmpty() {
        let data = Data()
        XCTAssertEqual(data.hexString, "")
    }

    func testDataHexStringSingleByte() {
        let data = Data([0xFF])
        XCTAssertEqual(data.hexString, "ff")
    }

    func testDataHexStringMultipleBytes() {
        let data = Data([0x00, 0x0A, 0x1B, 0xFF])
        XCTAssertEqual(data.hexString, "000a1bff")
    }

    func testDataHexStringKnownSHA256() {
        // SHA256 of empty string is well-known
        let hash = Data(SHA256.hash(data: Data()))
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertEqual(hash.hexString, expected)
    }

    // MARK: - AWSConfig constants

    func testAWSConfigRegion() {
        XCTAssertEqual(AWSConfig.region, "ap-southeast-2")
    }

    func testAWSConfigCognitoPoolIdHasRegionPrefix() {
        XCTAssertTrue(AWSConfig.cognitoIdentityPoolId.hasPrefix("ap-southeast-2:"))
    }

    func testAWSConfigAPIGatewayURLIsHTTPS() {
        XCTAssertTrue(AWSConfig.apiGatewayURL.hasPrefix("https://"))
    }

    func testAWSConfigS3BucketNotEmpty() {
        XCTAssertFalse(AWSConfig.s3Bucket.isEmpty)
    }

    // MARK: - AWSCredentials struct

    func testAWSCredentialsStoresValues() {
        let creds = CognitoAuthService.AWSCredentials(
            accessKeyId: "AKID",
            secretKey: "SECRET",
            sessionToken: "TOKEN",
            expiration: Date(timeIntervalSince1970: 1000)
        )
        XCTAssertEqual(creds.accessKeyId, "AKID")
        XCTAssertEqual(creds.secretKey, "SECRET")
        XCTAssertEqual(creds.sessionToken, "TOKEN")
        XCTAssertEqual(creds.expiration, Date(timeIntervalSince1970: 1000))
    }

    // MARK: - SyncService initial state

    func testSyncServiceInitialState() throws {
        let authService = CognitoAuthService()
        let apiClient = APIClient(authService: authService)

        let schema = Schema([
            DiaryEntry.self,
            CheckInTemplate.self,
            CheckInValue.self,
            PhotoAsset.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)

        let networkMonitor = NetworkMonitor()
        let syncService = SyncService(apiClient: apiClient, authService: authService, container: container, networkMonitor: networkMonitor)
        XCTAssertFalse(syncService.isSyncing)
        XCTAssertNil(syncService.lastError)
    }
}
