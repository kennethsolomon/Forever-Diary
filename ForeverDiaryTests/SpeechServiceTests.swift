import XCTest
@testable import ForeverDiary

final class SpeechServiceTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Clean up UserDefaults to avoid test pollution
        UserDefaults.standard.removeObject(forKey: "speechEngine")
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
        UserDefaults.standard.removeObject(forKey: "whisperServerURL")
    }

    // MARK: - SpeechEngineType

    func testSpeechEngineTypeRawValues() {
        XCTAssertEqual(SpeechEngineType.localServer.rawValue, "localserver")
        XCTAssertEqual(SpeechEngineType.apple.rawValue, "apple")
        XCTAssertEqual(SpeechEngineType.whisperKit.rawValue, "whisperkit")
    }

    func testSpeechEngineTypeDisplayNames() {
        XCTAssertEqual(SpeechEngineType.localServer.displayName, "Local Server")
        XCTAssertEqual(SpeechEngineType.apple.displayName, "Apple Speech")
        XCTAssertEqual(SpeechEngineType.whisperKit.displayName, "WhisperKit")
    }

    func testSpeechEngineTypeShortNames() {
        XCTAssertEqual(SpeechEngineType.localServer.shortName, "Server")
        XCTAssertEqual(SpeechEngineType.whisperKit.shortName, "Whisper")
        XCTAssertEqual(SpeechEngineType.apple.shortName, "Apple")
    }

    func testSpeechEngineTypeSymbolNames() {
        XCTAssertEqual(SpeechEngineType.localServer.symbolName, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(SpeechEngineType.whisperKit.symbolName, "cpu")
        XCTAssertEqual(SpeechEngineType.apple.symbolName, "mic")
    }

    func testSpeechEngineTypeAllCasesCount() {
        XCTAssertEqual(SpeechEngineType.allCases.count, 3)
    }

    func testSpeechEngineTypeInitFromRawValue() {
        XCTAssertEqual(SpeechEngineType(rawValue: "localserver"), .localServer)
        XCTAssertEqual(SpeechEngineType(rawValue: "apple"), .apple)
        XCTAssertEqual(SpeechEngineType(rawValue: "whisperkit"), .whisperKit)
    }

    func testSpeechEngineTypeInitFromInvalidRawValue() {
        XCTAssertNil(SpeechEngineType(rawValue: "siri"))
        XCTAssertNil(SpeechEngineType(rawValue: ""))
        XCTAssertNil(SpeechEngineType(rawValue: "Apple")) // case-sensitive
    }

    // MARK: - WhisperModelState

    func testWhisperModelStateEquatable() {
        XCTAssertEqual(WhisperModelState.notDownloaded, .notDownloaded)
        XCTAssertEqual(WhisperModelState.downloading, .downloading)
        XCTAssertEqual(WhisperModelState.downloaded, .downloaded)
        XCTAssertEqual(WhisperModelState.error("fail"), .error("fail"))
    }

    func testWhisperModelStateDifferentErrorsNotEqual() {
        XCTAssertNotEqual(WhisperModelState.error("a"), .error("b"))
    }

    func testWhisperModelStateDifferentCasesNotEqual() {
        XCTAssertNotEqual(WhisperModelState.notDownloaded, .downloaded)
        XCTAssertNotEqual(WhisperModelState.downloading, .downloaded)
        XCTAssertNotEqual(WhisperModelState.downloaded, .error("x"))
    }

    // MARK: - SpeechService Initial State

    func testInitialIsRecordingIsFalse() {
        let service = SpeechService()
        XCTAssertFalse(service.isRecording)
    }

    func testInitialIsProcessingIsFalse() {
        let service = SpeechService()
        XCTAssertFalse(service.isProcessing)
    }

    func testInitialTranscribedTextIsEmpty() {
        let service = SpeechService()
        XCTAssertEqual(service.transcribedText, "")
    }

    func testInitialAudioLevelsAreFiveZeros() {
        let service = SpeechService()
        XCTAssertEqual(service.audioLevels, [0, 0, 0, 0, 0])
    }

    func testInitialErrorIsNil() {
        let service = SpeechService()
        XCTAssertNil(service.error)
    }

    func testInitialTimeRemainingIs300() {
        let service = SpeechService()
        XCTAssertEqual(service.timeRemaining, 300)
    }

    // MARK: - Engine Choice (UserDefaults-backed)

    func testEngineChoiceDefaultsToApple() {
        UserDefaults.standard.removeObject(forKey: "speechEngine")
        let service = SpeechService()
        XCTAssertEqual(service.engineChoice, .apple)
    }

    func testEngineChoiceSetPersistsToUserDefaults() {
        let service = SpeechService()
        service.engineChoice = .whisperKit
        XCTAssertEqual(UserDefaults.standard.string(forKey: "speechEngine"), "whisperkit")
    }

    func testEngineChoiceGetReadsFromUserDefaults() {
        UserDefaults.standard.set("whisperkit", forKey: "speechEngine")
        let service = SpeechService()
        XCTAssertEqual(service.engineChoice, .whisperKit)
    }

    func testEngineChoiceInvalidUserDefaultsFallsBackToApple() {
        UserDefaults.standard.set("invalidEngine", forKey: "speechEngine")
        let service = SpeechService()
        XCTAssertEqual(service.engineChoice, .apple)
    }

    // MARK: - Language Identifier (UserDefaults-backed)

    func testLanguageIdentifierDefaultsToAuto() {
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
        let service = SpeechService()
        XCTAssertEqual(service.languageIdentifier, "auto")
    }

    func testLanguageIdentifierSetPersistsToUserDefaults() {
        let service = SpeechService()
        service.languageIdentifier = "tl"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "speechLanguage"), "tl")
    }

    func testLanguageIdentifierGetReadsFromUserDefaults() {
        UserDefaults.standard.set("ja", forKey: "speechLanguage")
        let service = SpeechService()
        XCTAssertEqual(service.languageIdentifier, "ja")
    }

    // MARK: - Supported Languages

    func testWhisperSupportedLanguagesIsNotEmpty() {
        let languages = SpeechService.whisperSupportedLanguages
        XCTAssertFalse(languages.isEmpty, "whisperSupportedLanguages should contain at least one language")
    }

    func testWhisperSupportedLanguagesContainsTagalog() {
        let languages = SpeechService.whisperSupportedLanguages
        XCTAssertTrue(languages.contains { $0.code == "tl" }, "Should contain Filipino (Tagalog)")
    }

    func testWhisperSupportedLanguagesAreSortedAlphabetically() {
        let languages = SpeechService.whisperSupportedLanguages
        let names = languages.map { $0.name }
        XCTAssertEqual(names, names.sorted(), "whisperSupportedLanguages should be sorted by name")
    }

    // MARK: - Display Name

    func testDisplayNameForKnownCode() {
        XCTAssertEqual(SpeechService.displayName(for: "en"), "English")
        XCTAssertEqual(SpeechService.displayName(for: "tl"), "Filipino (Tagalog)")
        XCTAssertEqual(SpeechService.displayName(for: "auto"), "Auto-detect")
    }

    // MARK: - Current Locale Display Name

    func testCurrentLocaleDisplayNameReturnsNonEmptyString() {
        let service = SpeechService()
        service.languageIdentifier = "en"
        XCTAssertFalse(service.currentLocaleDisplayName.isEmpty)
    }

    func testCurrentLocaleDisplayNameMatchesSetLanguage() {
        let service = SpeechService()
        service.languageIdentifier = "en"
        let displayName = service.currentLocaleDisplayName
        XCTAssertEqual(displayName, "English")
    }

    // MARK: - Cancel Recording (state reset)

    @MainActor
    func testCancelRecordingResetsState() {
        let service = SpeechService()
        service.cancelRecording()

        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isProcessing)
        XCTAssertEqual(service.transcribedText, "")
        XCTAssertEqual(service.audioLevels, [0, 0, 0, 0, 0])
    }

    // MARK: - Stop Recording when not recording

    @MainActor
    func testStopRecordingWhenNotRecordingReturnsEmpty() async {
        let service = SpeechService()
        let result = await service.stopRecording()
        XCTAssertEqual(result, "", "stopRecording when not recording should return empty transcribedText")
    }

    // MARK: - Delete Whisper Model

    @MainActor
    func testDeleteWhisperModelSetsStateToNotDownloaded() {
        let service = SpeechService()
        service.deleteWhisperModel()
        XCTAssertEqual(service.whisperModelState, .notDownloaded)
    }

    // MARK: - Clean Transcription

    func testCleanTranscriptionRemovesBracketedTokens() {
        let input = "Hello [cough] world"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Hello world")
    }

    func testCleanTranscriptionRemovesParenthesizedTokens() {
        let input = "Hello (laughter) world"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Hello world")
    }

    func testCleanTranscriptionRemovesMultipleTokens() {
        let input = "[music] Hello [cough] how are you (applause) today [BLANK_AUDIO]"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Hello how are you today")
    }

    func testCleanTranscriptionPreservesNormalText() {
        let input = "Kumain na ako kanina sa labas"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Kumain na ako kanina sa labas")
    }

    func testCleanTranscriptionHandlesEmptyString() {
        XCTAssertEqual(SpeechService.cleanTranscription(""), "")
    }

    func testCleanTranscriptionHandlesOnlyNoiseTokens() {
        let input = "[cough] [music] (silence)"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "")
    }

    func testCleanTranscriptionCollapsesMultipleSpaces() {
        let input = "Hello  [cough]   world"
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Hello world")
    }

    func testCleanTranscriptionTrimsWhitespace() {
        let input = "  [cough] Hello world [music]  "
        XCTAssertEqual(SpeechService.cleanTranscription(input), "Hello world")
    }

    // MARK: - Apple Speech Locale Mapping

    func testWhisperCodeToAppleLocaleReturnsCorrectMapping() {
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("en"), "en-US")
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("ja"), "ja-JP")
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("ko"), "ko-KR")
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("zh"), "zh-CN")
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("de"), "de-DE")
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("fr"), "fr-FR")
    }

    func testWhisperCodeToAppleLocaleReturnsNilForUnsupported() {
        XCTAssertNil(SpeechService.whisperCodeToAppleLocale("tl"), "Tagalog has no Apple Speech support")
        XCTAssertNil(SpeechService.whisperCodeToAppleLocale("haw"), "Hawaiian has no Apple Speech support")
        XCTAssertNil(SpeechService.whisperCodeToAppleLocale("la"), "Latin has no Apple Speech support")
    }

    func testWhisperCodeToAppleLocaleReturnsNilForInvalidCode() {
        XCTAssertNil(SpeechService.whisperCodeToAppleLocale("xyz"))
        XCTAssertNil(SpeechService.whisperCodeToAppleLocale(""))
    }

    func testWhisperCodeToAppleLocaleCantoneseMapping() {
        XCTAssertEqual(SpeechService.whisperCodeToAppleLocale("yue"), "zh-HK")
    }

    // MARK: - Favorite Languages

    func testFavoriteLanguagesDefaultsToEnglishAndTagalog() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        XCTAssertEqual(service.favoriteLanguages, ["en", "tl"])
    }

    func testAddFavoriteAppendsLanguage() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        service.addFavorite("ja")
        XCTAssertEqual(service.favoriteLanguages, ["en", "tl", "ja"])
    }

    func testAddFavoriteDoesNotDuplicate() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        service.addFavorite("en") // already in defaults
        XCTAssertEqual(service.favoriteLanguages, ["en", "tl"])
    }

    func testAddFavoriteCapsAtFive() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        // Default is ["en", "tl"] — add 3 more to reach 5
        service.addFavorite("ja")
        service.addFavorite("ko")
        service.addFavorite("zh")
        XCTAssertEqual(service.favoriteLanguages.count, 5)
        // 6th should be rejected
        service.addFavorite("fr")
        XCTAssertEqual(service.favoriteLanguages.count, 5)
        XCTAssertFalse(service.favoriteLanguages.contains("fr"))
    }

    func testRemoveFavoriteRemovesLanguage() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        service.removeFavorite("tl")
        XCTAssertEqual(service.favoriteLanguages, ["en"])
    }

    func testRemoveFavoriteNoOpForAbsentLanguage() {
        UserDefaults.standard.removeObject(forKey: "speechFavoriteLanguages")
        let service = SpeechService()
        service.removeFavorite("xyz")
        XCTAssertEqual(service.favoriteLanguages, ["en", "tl"])
    }

    func testFavoriteLanguagesPersistsToUserDefaults() {
        let service = SpeechService()
        service.addFavorite("de")
        let stored = UserDefaults.standard.stringArray(forKey: "speechFavoriteLanguages")
        XCTAssertNotNil(stored)
        XCTAssertTrue(stored!.contains("de"))
    }

    // MARK: - Display Name Edge Cases

    func testDisplayNameForUnknownCodeReturnsCode() {
        XCTAssertEqual(SpeechService.displayName(for: "xyz"), "xyz")
    }

    func testDisplayNameForEmptyStringReturnsEmpty() {
        XCTAssertEqual(SpeechService.displayName(for: ""), "")
    }

    // MARK: - Language List Data Integrity

    func testWhisperSupportedLanguagesHaveUniqueCodesAndNames() {
        let languages = SpeechService.whisperSupportedLanguages
        let codes = Set(languages.map { $0.code })
        let names = Set(languages.map { $0.name })
        XCTAssertEqual(codes.count, languages.count, "Language codes must be unique")
        XCTAssertEqual(names.count, languages.count, "Language names must be unique")
    }

    func testWhisperSupportedLanguagesContainsKeyLanguages() {
        let codes = Set(SpeechService.whisperSupportedLanguages.map { $0.code })
        let required = ["en", "tl", "ja", "ko", "zh", "es", "fr", "de", "ar", "hi", "pt", "ru"]
        for code in required {
            XCTAssertTrue(codes.contains(code), "Missing required language: \(code)")
        }
    }

    func testWhisperSupportedLanguagesCodesAreNonEmpty() {
        for lang in SpeechService.whisperSupportedLanguages {
            XCTAssertFalse(lang.code.isEmpty, "Language code should not be empty")
            XCTAssertFalse(lang.name.isEmpty, "Language name should not be empty for code: \(lang.code)")
        }
    }

    // MARK: - Current Locale Display Name for Auto

    func testCurrentLocaleDisplayNameForAutoShowsAutoDetect() {
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
        let service = SpeechService()
        XCTAssertEqual(service.currentLocaleDisplayName, "Auto-detect")
    }

    // MARK: - ServerConnectionState

    func testServerConnectionStateEquatable() {
        XCTAssertEqual(ServerConnectionState.untested, .untested)
        XCTAssertEqual(ServerConnectionState.testing, .testing)
        XCTAssertEqual(ServerConnectionState.connected, .connected)
        XCTAssertEqual(ServerConnectionState.failed("timeout"), .failed("timeout"))
    }

    func testServerConnectionStateDifferentFailuresNotEqual() {
        XCTAssertNotEqual(ServerConnectionState.failed("a"), .failed("b"))
    }

    func testServerConnectionStateDifferentCasesNotEqual() {
        XCTAssertNotEqual(ServerConnectionState.untested, .connected)
        XCTAssertNotEqual(ServerConnectionState.testing, .connected)
        XCTAssertNotEqual(ServerConnectionState.connected, .failed("x"))
    }

    // MARK: - Server URL (UserDefaults-backed)

    func testServerURLDefaultsToLocalhost() {
        UserDefaults.standard.removeObject(forKey: "whisperServerURL")
        let service = SpeechService()
        XCTAssertEqual(service.serverURL, "http://localhost:8080")
    }

    func testServerURLSetPersistsToUserDefaults() {
        let service = SpeechService()
        service.serverURL = "http://192.168.1.5:9090"
        XCTAssertEqual(UserDefaults.standard.string(forKey: "whisperServerURL"), "http://192.168.1.5:9090")
    }

    func testServerURLGetReadsFromUserDefaults() {
        UserDefaults.standard.set("http://10.0.0.1:8080", forKey: "whisperServerURL")
        let service = SpeechService()
        XCTAssertEqual(service.serverURL, "http://10.0.0.1:8080")
    }

    // MARK: - Initial Server Connection State

    func testInitialServerConnectionStateIsUntested() {
        let service = SpeechService()
        XCTAssertEqual(service.serverConnectionState, .untested)
    }

    // MARK: - Engine Choice with Local Server

    func testEngineChoiceSetToLocalServer() {
        let service = SpeechService()
        service.engineChoice = .localServer
        XCTAssertEqual(UserDefaults.standard.string(forKey: "speechEngine"), "localserver")
    }

    func testEngineChoiceGetLocalServerFromUserDefaults() {
        UserDefaults.standard.set("localserver", forKey: "speechEngine")
        let service = SpeechService()
        XCTAssertEqual(service.engineChoice, .localServer)
    }

    // MARK: - SpeechEngineType allCases Order

    func testSpeechEngineTypeAllCasesOrder() {
        let cases = SpeechEngineType.allCases
        XCTAssertEqual(cases[0], .localServer)
        XCTAssertEqual(cases[1], .whisperKit)
        XCTAssertEqual(cases[2], .apple)
    }

    // MARK: - Test Server Connection

    @MainActor
    func testServerConnectionWithInvalidURL() async {
        let service = SpeechService()
        service.serverURL = ""
        await service.testServerConnection()
        if case .failed(let msg) = service.serverConnectionState {
            XCTAssertEqual(msg, "Invalid URL")
        } else {
            XCTFail("Expected .failed state for invalid URL, got \(service.serverConnectionState)")
        }
    }

    @MainActor
    func testServerConnectionWithUnreachableServer() async {
        let service = SpeechService()
        // Use a port that's almost certainly not running a server
        service.serverURL = "http://127.0.0.1:19999"
        await service.testServerConnection()
        if case .failed = service.serverConnectionState {
            // Expected — server is unreachable
        } else {
            XCTFail("Expected .failed state for unreachable server, got \(service.serverConnectionState)")
        }
    }

    // MARK: - Finish Session

    func testFinishSessionDoesNotCrashWithNoRecording() {
        let service = SpeechService()
        // Should not crash when there's no recording URL
        service.finishSession()
    }

    // MARK: - Retry Transcription Without Recording

    @MainActor
    func testRetryTranscriptionWithoutRecordingSetsError() async {
        let service = SpeechService()
        let result = await service.retryTranscription(using: .localServer)
        XCTAssertEqual(result, "")
        XCTAssertEqual(service.error, "No recording available to retry")
    }

    @MainActor
    func testRetryTranscriptionWithoutRecordingForWhisperKit() async {
        let service = SpeechService()
        let result = await service.retryTranscription(using: .whisperKit)
        XCTAssertEqual(result, "")
        XCTAssertEqual(service.error, "No recording available to retry")
    }

    @MainActor
    func testRetryTranscriptionWithoutRecordingForApple() async {
        let service = SpeechService()
        let result = await service.retryTranscription(using: .apple)
        XCTAssertEqual(result, "")
        XCTAssertEqual(service.error, "No recording available to retry")
    }
}
