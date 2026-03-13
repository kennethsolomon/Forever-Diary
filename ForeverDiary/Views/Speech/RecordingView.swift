import SwiftUI

struct RecordingView: View {
    @Environment(SpeechService.self) private var speechService
    @Environment(\.dismiss) private var dismiss

    let onTranscription: (String) -> Void

    @State private var showLanguagePicker = false

    var body: some View {
        VStack(spacing: 20) {
            // Top row: language pill + quick-switch favorites + time remaining
            HStack(spacing: 6) {
                languagePill

                quickSwitchPills

                Spacer()

                timeLabel
            }
            .padding(.top, 8)

            Spacer()

            // Waveform
            WaveformView(
                audioLevels: speechService.audioLevels,
                isActive: speechService.isRecording
            )
            .frame(height: 44)

            Spacer()

            // Live transcript
            transcriptArea

            // Status label
            statusLabel

            // Stop button
            stopButton
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .background(Color("backgroundPrimary"))
        .task {
            await speechService.startRecording()
        }
        .onDisappear {
            if speechService.isRecording || speechService.isProcessing {
                speechService.cancelRecording()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView()
        }
        #else
        .popover(isPresented: $showLanguagePicker) {
            LanguagePickerView()
                .frame(minWidth: 280, minHeight: 400)
        }
        #endif
    }

    // MARK: - Language Pill

    private var languagePill: some View {
        Button {
            showLanguagePicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(.caption2))
                Text(speechService.currentLocaleDisplayName)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(Color("textSecondary"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color("surfaceCard"))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick-Switch Pills

    @ViewBuilder
    private var quickSwitchPills: some View {
        let favorites = speechService.favoriteLanguages.filter { $0 != speechService.languageIdentifier }
        // Disable during Apple Speech recording — live recognizer uses the language set at start
        let isDisabled = speechService.isRecording && speechService.engineChoice == .apple
        if !favorites.isEmpty {
            HStack(spacing: 4) {
                ForEach(favorites, id: \.self) { code in
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            speechService.languageIdentifier = code
                        }
                    } label: {
                        Text(code.uppercased())
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(isDisabled ? Color("textSecondary").opacity(0.3) : Color("textSecondary"))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(Color("surfaceCard"))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                }
            }
        }
    }

    // MARK: - Time Label

    private var timeLabel: some View {
        Text(formattedTime)
            .font(.system(.caption, design: .rounded).monospacedDigit())
            .foregroundStyle(speechService.timeRemaining <= 30 ? Color("destructive") : Color("textSecondary"))
    }

    private var formattedTime: String {
        let minutes = Int(speechService.timeRemaining) / 60
        let seconds = Int(speechService.timeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(speechService.transcribedText.isEmpty ? " " : speechService.transcribedText)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(speechService.transcribedText.isEmpty
                        ? Color("textSecondary").opacity(0.4)
                        : Color("textPrimary"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("transcriptBottom")
            }
            .frame(maxHeight: 120)
            .onChange(of: speechService.transcribedText) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("transcriptBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Status

    private var statusLabel: some View {
        Group {
            if speechService.isProcessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing...")
                }
            } else if speechService.isRecording {
                Text(speechService.engineChoice == .apple ? "Listening..." : "Recording...")
            } else if let error = speechService.error {
                Text(error)
                    .foregroundStyle(Color("destructive"))
            } else {
                Text(" ")
            }
        }
        .font(.system(.caption, design: .rounded, weight: .medium))
        .foregroundStyle(Color("textSecondary"))
    }

    // MARK: - Stop / Done Button

    private var stopButton: some View {
        Group {
            if speechService.isRecording {
                Button {
                    Task {
                        let text = await speechService.stopRecording()
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onTranscription(text)
                        }
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.fill")
                            .font(.system(size: 12))
                        Text("Stop")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 44)
                    .background(Capsule().fill(Color("destructive")))
                }
                .buttonStyle(.plain)
            } else if !speechService.isProcessing && !speechService.transcribedText.isEmpty {
                // Timer expired — recording stopped, result ready
                Button {
                    let text = speechService.transcribedText
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onTranscription(text)
                    }
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Done")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 44)
                    .background(Capsule().fill(Color("accentBright")))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Language Picker

struct LanguagePickerView: View {
    @Environment(SpeechService.self) private var speechService
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var filteredLanguages: [(code: String, name: String)] {
        if searchText.isEmpty {
            return SpeechService.whisperSupportedLanguages
        }
        return SpeechService.whisperSupportedLanguages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var favoritesForDisplay: [(code: String, name: String)] {
        speechService.favoriteLanguages.compactMap { code in
            SpeechService.whisperSupportedLanguages.first { $0.code == code }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Favorites section
                Section {
                    // Auto-detect row
                    languageRow(code: "auto", name: "Auto-detect", isFavorite: false)

                    ForEach(favoritesForDisplay, id: \.code) { lang in
                        languageRow(code: lang.code, name: lang.name, isFavorite: true)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    speechService.removeFavorite(lang.code)
                                } label: {
                                    Label("Remove", systemImage: "star.slash")
                                }
                                .tint(Color("destructive"))
                            }
                    }
                } header: {
                    Text("Favorites")
                }

                // All languages section
                Section {
                    ForEach(filteredLanguages, id: \.code) { lang in
                        let isFav = speechService.favoriteLanguages.contains(lang.code)

                        languageRow(code: lang.code, name: lang.name, isFavorite: false)
                            .swipeActions(edge: .leading) {
                                if !isFav {
                                    Button {
                                        speechService.addFavorite(lang.code)
                                    } label: {
                                        Label("Favorite", systemImage: "star.fill")
                                    }
                                    .tint(Color("accentBright"))
                                }
                            }
                    }
                } header: {
                    Text("All Languages")
                }
            }
            #if os(iOS)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            #else
            .searchable(text: $searchText, prompt: "Search languages")
            #endif
            .navigationTitle("Language")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func languageRow(code: String, name: String, isFavorite: Bool) -> some View {
        Button {
            speechService.languageIdentifier = code
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(.caption2))
                            .foregroundStyle(Color("accentBright"))
                    }
                    Text(name)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color("textPrimary"))
                    Spacer()
                    if speechService.languageIdentifier == code {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color("accentBright"))
                    }
                }

                // Show Apple Speech unsupported note
                if code != "auto" && speechService.engineChoice == .apple && SpeechService.whisperCodeToAppleLocale(code) == nil {
                    Text("Not supported by Apple Speech — WhisperKit will be used")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color("textSecondary"))
                }
            }
        }
    }
}
