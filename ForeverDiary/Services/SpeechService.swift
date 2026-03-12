import Foundation
import Speech
import AVFoundation
import Observation

#if canImport(WhisperKit)
import WhisperKit
#endif

// MARK: - Types

enum SpeechEngineType: String, CaseIterable {
    case apple = "apple"
    case whisperKit = "whisperkit"

    var displayName: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisperKit: return "WhisperKit"
        }
    }
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

    // MARK: Settings (UserDefaults-backed)

    var engineChoice: SpeechEngineType {
        get { SpeechEngineType(rawValue: UserDefaults.standard.string(forKey: "speechEngine") ?? "apple") ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "speechEngine") }
    }

    var languageIdentifier: String {
        get { UserDefaults.standard.string(forKey: "speechLanguage") ?? Locale.current.identifier }
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
    @ObservationIgnored private var levelTimerTask: Task<Void, Never>?
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
    func stopRecording() async -> String {
        guard isRecording else { return transcribedText }

        isRecording = false
        timerTask?.cancel()
        levelTimerTask?.cancel()

        // Finalize audio engine and get recorded file URL
        let fileURL = finishAudioEngine()

        // Get primary result
        var result = ""

        if engineChoice == .apple {
            result = finishAppleSpeechRecognition()
        } else {
            // WhisperKit primary — transcribe recorded file
            if let url = fileURL {
                isProcessing = true
                result = await transcribeWithWhisperKit(url: url)
                isProcessing = false
            }
        }

        // Fallback if primary returned empty
        if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = fileURL {
            let fallback: SpeechEngineType = engineChoice == .apple ? .whisperKit : .apple
            isProcessing = true
            if fallback == .whisperKit {
                result = await transcribeWithWhisperKit(url: url)
            } else {
                result = await transcribeFileWithAppleSpeech(url: url)
            }
            isProcessing = false
        }

        transcribedText = result
        audioLevels = [0, 0, 0, 0, 0]
        return result
    }

    // MARK: - Cancel Recording

    @MainActor
    func cancelRecording() {
        isRecording = false
        isProcessing = false
        timerTask?.cancel()
        levelTimerTask?.cancel()
        _ = finishAudioEngine()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcribedText = ""
        audioLevels = [0, 0, 0, 0, 0]
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

        // Set up Apple Speech if it's the primary engine (for live streaming)
        if engineChoice == .apple {
            let locale = Locale(identifier: languageIdentifier)
            speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()

            guard let speechRecognizer, speechRecognizer.isAvailable else {
                throw NSError(domain: "SpeechService", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Speech recognition not available for \(locale.identifier)."])
            }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest?.shouldReportPartialResults = true
            if speechRecognizer.supportsOnDeviceRecognition {
                recognitionRequest?.requiresOnDeviceRecognition = true
            }

            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, taskError in
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

        // Install tap: write to file + feed Apple Speech + compute audio levels
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Write to file (always, for fallback support)
            self.fileWriteQueue.sync {
                try? self.audioFile?.write(from: buffer)
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
        let locale = Locale(identifier: languageIdentifier)
        let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return "" }

        let request = SFSpeechURLRecognitionRequest(url: url)

        return await withCheckedContinuation { continuation in
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

    // MARK: - WhisperKit Transcription

    private func transcribeWithWhisperKit(url: URL) async -> String {
        #if canImport(WhisperKit)
        do {
            if whisperKit == nil {
                whisperKit = try await WhisperKit(model: "openai_whisper-base", verbose: false)
            }
            guard let whisperKit else { return "" }

            let results = try await whisperKit.transcribe(audioPath: url.path())
            return results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
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
            whisperKit = try await WhisperKit(model: "openai_whisper-base", verbose: false)
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

    static var supportedLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales()
            .sorted { ($0.localizedString(forIdentifier: $0.identifier) ?? "") < ($1.localizedString(forIdentifier: $1.identifier) ?? "") }
            .map { Locale(identifier: $0.identifier) }
    }

    var currentLocaleDisplayName: String {
        let locale = Locale(identifier: languageIdentifier)
        return locale.localizedString(forIdentifier: languageIdentifier) ?? languageIdentifier
    }
}
