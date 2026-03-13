import XCTest
@testable import ForeverDiary

final class SpeechServiceTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        // Clean up UserDefaults to avoid test pollution
        UserDefaults.standard.removeObject(forKey: "speechEngine")
        UserDefaults.standard.removeObject(forKey: "speechLanguage")
    }

    // MARK: - SpeechEngineType

    func testSpeechEngineTypeRawValues() {
        XCTAssertEqual(SpeechEngineType.apple.rawValue, "apple")
        XCTAssertEqual(SpeechEngineType.whisperKit.rawValue, "whisperkit")
    }

    func testSpeechEngineTypeDisplayNames() {
        XCTAssertEqual(SpeechEngineType.apple.displayName, "Apple Speech")
        XCTAssertEqual(SpeechEngineType.whisperKit.displayName, "WhisperKit")
    }

    func testSpeechEngineTypeAllCasesCount() {
        XCTAssertEqual(SpeechEngineType.allCases.count, 2)
    }

    func testSpeechEngineTypeInitFromRawValue() {
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
}
