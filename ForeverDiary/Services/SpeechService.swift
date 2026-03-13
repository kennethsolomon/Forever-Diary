import Foundation
import Speech
import AVFoundation
import Observation

#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Types

enum SpeechEngineType: String, CaseIterable {
    case localServer = "localserver"
    case whisperKit = "whisperkit"
    case apple = "apple"

    var displayName: String {
        switch self {
        case .localServer: return "Local Server"
        case .whisperKit: return "WhisperKit"
        case .apple: return "Apple Speech"
        }
    }

    var shortName: String {
        switch self {
        case .localServer: return "Server"
        case .whisperKit: return "Whisper"
        case .apple: return "Apple"
        }
    }

    var symbolName: String {
        switch self {
        case .localServer: return "antenna.radiowaves.left.and.right"
        case .whisperKit: return "cpu"
        case .apple: return "mic"
        }
    }
}

enum ServerConnectionState: Equatable {
    case untested
    case testing
    case connected
    case failed(String)
}

enum WhisperModelState: Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case error(String)
}

// MARK: - SpeechService

@Observable
final class SpeechService {

    // MARK: Public State

    private(set) var isRecording = false
    private(set) var isProcessing = false
    private(set) var transcribedText = ""
    private(set) var audioLevels: [Float] = [0, 0, 0, 0, 0]
    private(set) var error: String?
    private(set) var timeRemaining: TimeInterval = 300
    private(set) var whisperModelState: WhisperModelState = .notDownloaded
    private(set) var serverConnectionState: ServerConnectionState = .untested

    // MARK: Settings (UserDefaults-backed)

    var engineChoice: SpeechEngineType {
        get { SpeechEngineType(rawValue: UserDefaults.standard.string(forKey: "speechEngine") ?? "apple") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "speechEngine") }
    }

    var serverURL: String {
        get { UserDefaults.standard.string(forKey: "whisperServerURL") ?? "http://localhost:8080" }
        set { UserDefaults.standard.set(newValue, forKey: "whisperServerURL") }
    }

    var languageIdentifier: String {
        get { UserDefaults.standard.string(forKey: "speechLanguage") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "speechLanguage") }
    }

    // MARK: Private

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var recordingURL: URL?
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private let fileWriteQueue = DispatchQueue(label: "com.foreverdiary.speechFileWrite")
    @ObservationIgnored private let maxDuration: TimeInterval = 300

    #if canImport(WhisperKit)
    @ObservationIgnored private var whisperKit: WhisperKit?
    #endif

    // MARK: - Init

    init() {
        checkWhisperModelStatus()
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        #if os(iOS)
        let micStatus = await AVAudioApplication.requestRecordPermission()
        #else
        let micStatus = true // macOS shows system dialog on first AVAudioEngine use
        #endif

        return speechStatus && micStatus
    }

    // MARK: - Start Recording

    @MainActor
    func startRecording() async {
        guard !isRecording, !isProcessing else { return }

        let hasPermission = await requestPermissions()
        guard hasPermission else {
            error = "Microphone or speech recognition permission denied. Check Settings."
            return
        }

        error = nil
        transcribedText = ""
        timeRemaining = maxDuration
        audioLevels = [0, 0, 0, 0, 0]

        do {
            try startAudioEngine()
            isRecording = true
            startTimer()
        } catch {
            self.error = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    // MARK: - Stop Recording

    @MainActor
    func stopRecording(using engine: SpeechEngineType? = nil) async -> String {
        guard isRecording else { return transcribedText }

        isRecording = false
        timerTask?.cancel()

        // Finalize audio engine and get recorded file URL
        let fileURL = finishAudioEngine()

        // Dispatch to selected engine — no automatic fallback
        let activeEngine = engine ?? engineChoice
        var result = ""

        switch activeEngine {
        case .localServer:
            if let url = fileURL {
                isProcessing = true
                result = await transcribeWithLocalServer(url: url)
                isProcessing = false
            }
        case .whisperKit:
            if let url = fileURL {
                isProcessing = true
                result = await transcribeWithWhisperKit(url: url)
                isProcessing = false
            }
        case .apple:
            result = finishAppleSpeechRecognition()
            // If live recognition returned empty, try file-based transcription
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = fileURL {
                isProcessing = true
                result = await transcribeFileWithAppleSpeech(url: url)
                isProcessing = false
            }
        }

        transcribedText = result
        audioLevels = [0, 0, 0, 0, 0]
        // Don't cleanup temp file here — keep it for retry. Cleanup on cancel or dismiss.
        return result
    }

    @MainActor
    func retryTranscription(using engine: SpeechEngineType) async -> String {
        guard let url = recordingURL, FileManager.default.fileExists(atPath: url.path) else {
            error = "No recording available to retry"
            return ""
        }

        error = nil
        isProcessing = true

        var result = ""
        switch engine {
        case .localServer:
            result = await transcribeWithLocalServer(url: url)
        case .whisperKit:
            result = await transcribeWithWhisperKit(url: url)
        case .apple:
            result = await transcribeFileWithAppleSpeech(url: url)
        }

        isProcessing = false
        transcribedText = result
        return result
    }

    // MARK: - Cancel Recording

    @MainActor
    func cancelRecording() {
        isRecording = false
        isProcessing = false
        timerTask?.cancel()
        _ = finishAudioEngine()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcribedText = ""
        audioLevels = [0, 0, 0, 0, 0]
        cleanupTempFile()
    }

    func finishSession() {
        cleanupTempFile()
    }

    private func cleanupTempFile() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
    }

    // MARK: - Audio Engine (shared for both engines)

    private func startAudioEngine() throws {
        // Prepare temp file for recording
        recordingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("diary_speech_\(UUID().uuidString).wav")

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        audioEngine = AVAudioEngine()
        guard let audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Open audio file for writing
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            audioFile = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
        }

        // Set up Apple Speech if it's the primary engine and language is supported
        let appleLocale: String? = languageIdentifier == "auto"
            ? Locale.current.identifier
            : Self.whisperCodeToAppleLocale(languageIdentifier)

        if engineChoice == .apple, let localeId = appleLocale {
            let locale = Locale(identifier: localeId)
            speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()

            if let speechRecognizer, speechRecognizer.isAvailable {
                recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
                recognitionRequest?.shouldReportPartialResults = true
                if speechRecognizer.supportsOnDeviceRecognition {
                    recognitionRequest?.requiresOnDeviceRecognition = true
                }

                guard let request = recognitionRequest else { return }
                recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, taskError in
                    guard let self else { return }
                    if let result {
                        Task { @MainActor in
                            self.transcribedText = result.bestTranscription.formattedString
                        }
                    }
                    if let taskError, (taskError as NSError).code != 216 {
                        Task { @MainActor in
                            self.error = taskError.localizedDescription
                        }
                    }
                }
            }
            // If not available, fall through to record-only mode (WhisperKit fallback at stop)
        }

        // Install tap: write to file + feed Apple Speech + compute audio levels
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Write to file (always, for fallback support)
            // Use async to avoid blocking the real-time audio thread
            self.fileWriteQueue.async {
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    print("[SpeechService] Audio file write failed: \(error.localizedDescription)")
                }
            }

            // Feed Apple Speech recognition
            self.recognitionRequest?.append(buffer)

            // Compute audio level
            self.computeAudioLevel(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func finishAudioEngine() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        fileWriteQueue.sync {
            self.audioFile = nil // Close file
        }

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif

        return recordingURL
    }

    // MARK: - Apple Speech Recognition

    private func finishAppleSpeechRecognition() -> String {
        recognitionRequest?.endAudio()
        let text = transcribedText
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
        return text
    }

    private func transcribeFileWithAppleSpeech(url: URL) async -> String {
        let localeId = languageIdentifier == "auto"
            ? Locale.current.identifier
            : (Self.whisperCodeToAppleLocale(languageIdentifier) ?? Locale.current.identifier)
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)

        return await withTaskGroup(of: String.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    var hasResumed = false
                    recognizer.recognitionTask(with: request) { result, taskError in
                        guard !hasResumed else { return }
                        if let result, result.isFinal {
                            hasResumed = true
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        } else if taskError != nil {
                            hasResumed = true
                            continuation.resume(returning: "")
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(30))
                return ""
            }
            let first = await group.next() ?? ""
            group.cancelAll()
            return first
        }
    }

    // MARK: - Local Server Transcription

    @MainActor
    func testServerConnection() async {
        serverConnectionState = .testing
        let urlString = serverURL.trimmingCharacters(in: .whitespaces)
        guard !urlString.isEmpty,
              urlString.hasPrefix("http"),
              let url = URL(string: urlString) else {
            serverConnectionState = .failed("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                let server = http.value(forHTTPHeaderField: "Server") ?? ""
                if server.lowercased().contains("whisper") {
                    serverConnectionState = .connected
                } else {
                    serverConnectionState = .failed("Not a Whisper server")
                }
            } else {
                serverConnectionState = .failed("Unexpected response")
            }
        } catch {
            serverConnectionState = .failed("Unreachable")
        }
    }

    private func transcribeWithLocalServer(url fileURL: URL) async -> String {
        let urlString = serverURL.trimmingCharacters(in: .whitespaces)
        guard let endpoint = URL(string: "\(urlString)/inference") else {
            await MainActor.run { self.error = "Invalid server URL: \(urlString)" }
            return ""
        }

        do {
            let audioData = try Data(contentsOf: fileURL)
            let boundary = UUID().uuidString

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            var body = Data()

            // file field
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
            body.appendString("Content-Type: audio/wav\r\n\r\n")
            body.append(audioData)
            body.appendString("\r\n")

            // temperature field
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
            body.appendString("0.0\r\n")

            // response_format field
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
            body.appendString("json\r\n")

            // language field
            if languageIdentifier != "auto" {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
                body.appendString("\(languageIdentifier)\r\n")
            }

            body.appendString("--\(boundary)--\r\n")
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                await MainActor.run { self.error = "Invalid response from server" }
                return ""
            }

            guard (200...299).contains(http.statusCode) else {
                await MainActor.run { self.error = "Server error (HTTP \(http.statusCode))" }
                return ""
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let text = json["text"] as? String {
                return Self.cleanTranscription(text)
            }

            await MainActor.run { self.error = "Unexpected response format from server" }
            return ""
        } catch let error as URLError where error.code == .timedOut {
            await MainActor.run { self.error = "Server timed out" }
            return ""
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .notConnectedToInternet {
            await MainActor.run { self.error = "Server unreachable at \(urlString)" }
            return ""
        } catch {
            await MainActor.run { self.error = "Server error: \(error.localizedDescription)" }
            return ""
        }
    }

    // MARK: - WhisperKit Transcription

    private func transcribeWithWhisperKit(url: URL) async -> String {
        #if canImport(WhisperKit)
        do {
            if whisperKit == nil {
                whisperKit = try await WhisperKit(model: "openai_whisper-small", verbose: false)
            }
            guard let whisperKit else { return "" }

            var options = DecodingOptions()
            if languageIdentifier != "auto" {
                options.language = languageIdentifier
            }

            let results = try await whisperKit.transcribe(audioPath: url.path(), decodeOptions: options)
            let raw = results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.cleanTranscription(raw)
        } catch {
            await MainActor.run {
                self.error = "WhisperKit transcription failed: \(error.localizedDescription)"
            }
            return ""
        }
        #else
        return ""
        #endif
    }

    // MARK: - WhisperKit Model Management

    @MainActor
    func downloadWhisperModel() async {
        #if canImport(WhisperKit)
        whisperModelState = .downloading
        do {
            whisperKit = try await WhisperKit(model: "openai_whisper-small", verbose: false)
            whisperModelState = .downloaded
        } catch {
            whisperModelState = .error(error.localizedDescription)
        }
        #endif
    }

    @MainActor
    func deleteWhisperModel() {
        #if canImport(WhisperKit)
        whisperKit = nil
        #endif
        whisperModelState = .notDownloaded

        // Clean up cached model files
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let huggingfaceDir = appSupport.appendingPathComponent("huggingface")
            try? FileManager.default.removeItem(at: huggingfaceDir)
        }
    }

    func checkWhisperModelStatus() {
        #if canImport(WhisperKit)
        if whisperKit != nil {
            whisperModelState = .downloaded
            return
        }
        #endif

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let modelDir = appSupport.appendingPathComponent("huggingface")
            if FileManager.default.fileExists(atPath: modelDir.path) {
                whisperModelState = .downloaded
                return
            }
        }
        whisperModelState = .notDownloaded
    }

    // MARK: - Transcription Cleanup

    static func cleanTranscription(_ text: String) -> String {
        // Strip noise tokens like [cough], [music], (laughter), [BLANK_AUDIO], etc.
        let pattern = #"\[[\w\s]+\]|\([\w\s]+\)"#
        let cleaned = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        // Collapse multiple spaces into one and trim
        return cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Apple Speech Locale Mapping

    static func whisperCodeToAppleLocale(_ code: String) -> String? {
        let mapping: [String: String] = [
            "af": "af-ZA", "ar": "ar-SA", "bg": "bg-BG", "bn": "bn-IN",
            "ca": "ca-ES", "cs": "cs-CZ", "cy": "cy-GB", "da": "da-DK",
            "de": "de-DE", "el": "el-GR", "en": "en-US", "es": "es-ES",
            "et": "et-EE", "fa": "fa-IR", "fi": "fi-FI", "fr": "fr-FR",
            "gl": "gl-ES", "gu": "gu-IN", "he": "he-IL", "hi": "hi-IN",
            "hr": "hr-HR", "hu": "hu-HU", "hy": "hy-AM", "id": "id-ID",
            "is": "is-IS", "it": "it-IT", "ja": "ja-JP", "ka": "ka-GE",
            "kn": "kn-IN", "ko": "ko-KR", "lt": "lt-LT", "lv": "lv-LV",
            "mk": "mk-MK", "ml": "ml-IN", "mr": "mr-IN", "ms": "ms-MY",
            "my": "my-MM", "ne": "ne-NP", "nl": "nl-NL", "no": "nb-NO",
            "pa": "pa-IN", "pl": "pl-PL", "pt": "pt-BR", "ro": "ro-RO",
            "ru": "ru-RU", "sk": "sk-SK", "sl": "sl-SI", "sq": "sq-AL",
            "sr": "sr-RS", "sv": "sv-SE", "sw": "sw-KE", "ta": "ta-IN",
            "te": "te-IN", "th": "th-TH", "tr": "tr-TR", "uk": "uk-UA",
            "ur": "ur-PK", "uz": "uz-UZ", "vi": "vi-VN", "zh": "zh-CN",
            "yue": "zh-HK",
        ]
        return mapping[code]
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while let self, self.isRecording, self.timeRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.timeRemaining -= 1
                if self.timeRemaining <= 0 {
                    _ = await self.stopRecording()
                }
            }
        }
    }

    // MARK: - Audio Level

    private func computeAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var sum: Float = 0
        for i in 0..<frames {
            sum += abs(channelData[0][i])
        }
        let mean = sum / Float(frames)
        let level = min(1.0, mean * 5)

        Task { @MainActor [weak self] in
            self?.audioLevels.removeFirst()
            self?.audioLevels.append(level)
        }
    }

    // MARK: - Supported Languages

    static let whisperSupportedLanguages: [(code: String, name: String)] = [
        ("af", "Afrikaans"), ("sq", "Albanian"), ("am", "Amharic"), ("ar", "Arabic"),
        ("hy", "Armenian"), ("as", "Assamese"), ("az", "Azerbaijani"), ("ba", "Bashkir"),
        ("eu", "Basque"), ("be", "Belarusian"), ("bn", "Bengali"), ("bs", "Bosnian"),
        ("br", "Breton"), ("bg", "Bulgarian"), ("yue", "Cantonese"), ("ca", "Catalan"),
        ("zh", "Chinese"), ("hr", "Croatian"), ("cs", "Czech"), ("da", "Danish"),
        ("nl", "Dutch"), ("en", "English"), ("et", "Estonian"), ("fo", "Faroese"),
        ("tl", "Filipino (Tagalog)"), ("fi", "Finnish"), ("fr", "French"), ("gl", "Galician"),
        ("ka", "Georgian"), ("de", "German"), ("el", "Greek"), ("gu", "Gujarati"),
        ("ht", "Haitian Creole"), ("ha", "Hausa"), ("haw", "Hawaiian"), ("he", "Hebrew"),
        ("hi", "Hindi"), ("hu", "Hungarian"), ("is", "Icelandic"), ("id", "Indonesian"),
        ("it", "Italian"), ("ja", "Japanese"), ("jw", "Javanese"), ("kn", "Kannada"),
        ("kk", "Kazakh"), ("km", "Khmer"), ("ko", "Korean"), ("lo", "Lao"),
        ("la", "Latin"), ("lv", "Latvian"), ("ln", "Lingala"), ("lt", "Lithuanian"),
        ("lb", "Luxembourgish"), ("mk", "Macedonian"), ("mg", "Malagasy"), ("ms", "Malay"),
        ("ml", "Malayalam"), ("mt", "Maltese"), ("mi", "Maori"), ("mr", "Marathi"),
        ("mn", "Mongolian"), ("my", "Myanmar"), ("ne", "Nepali"), ("no", "Norwegian"),
        ("nn", "Nynorsk"), ("oc", "Occitan"), ("ps", "Pashto"), ("fa", "Persian"),
        ("pl", "Polish"), ("pt", "Portuguese"), ("pa", "Punjabi"), ("ro", "Romanian"),
        ("ru", "Russian"), ("sa", "Sanskrit"), ("sr", "Serbian"), ("sn", "Shona"),
        ("sd", "Sindhi"), ("si", "Sinhala"), ("sk", "Slovak"), ("sl", "Slovenian"),
        ("so", "Somali"), ("es", "Spanish"), ("su", "Sundanese"), ("sw", "Swahili"),
        ("sv", "Swedish"), ("tg", "Tajik"), ("ta", "Tamil"), ("tt", "Tatar"),
        ("te", "Telugu"), ("th", "Thai"), ("bo", "Tibetan"), ("tr", "Turkish"),
        ("tk", "Turkmen"), ("uk", "Ukrainian"), ("ur", "Urdu"), ("uz", "Uzbek"),
        ("vi", "Vietnamese"), ("cy", "Welsh"), ("yi", "Yiddish"), ("yo", "Yoruba"),
    ]

    static func displayName(for code: String) -> String {
        if code == "auto" { return "Auto-detect" }
        return whisperSupportedLanguages.first { $0.code == code }?.name ?? code
    }

    var currentLocaleDisplayName: String {
        Self.displayName(for: languageIdentifier)
    }

    // MARK: - Favorite Languages

    var favoriteLanguages: [String] {
        get { UserDefaults.standard.stringArray(forKey: "speechFavoriteLanguages") ?? ["en", "tl"] }
        set { UserDefaults.standard.set(newValue, forKey: "speechFavoriteLanguages") }
    }

    func addFavorite(_ code: String) {
        var favorites = favoriteLanguages
        guard !favorites.contains(code), favorites.count < 5 else { return }
        favorites.append(code)
        favoriteLanguages = favorites
    }

    func removeFavorite(_ code: String) {
        var favorites = favoriteLanguages
        favorites.removeAll { $0 == code }
        favoriteLanguages = favorites
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
