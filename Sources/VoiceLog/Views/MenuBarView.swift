import SwiftUI

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var recordingService: AudioRecordingService
    @EnvironmentObject private var whisperService: WhisperService
    @EnvironmentObject private var notionService: NotionService

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            Divider()

            // Main content area based on current mode
            Group {
                switch appState.mode {
                case .idle:
                    idleView
                case .recording:
                    recordingView
                case .transcribing:
                    transcribingView
                case .processing:
                    processingView
                case .syncing:
                    syncingView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Meeting preview overlay
            if appState.showMeetingPreview, appState.currentMeeting != nil {
                Divider()
                MeetingPreviewView()
                    .environmentObject(appState)
                    .environmentObject(notionService)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            // Error banner
            if let error = appState.lastError {
                Divider()
                errorBanner(message: error)
            }

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 340)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "mic.circle.fill")
                .font(.title2)
                .foregroundStyle(appState.mode == .recording ? .red : .accentColor)
            Text("VoiceLog")
                .font(.headline)
            Spacer()
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 16) {
            Text("Ready to Record")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Button(action: startRecording) {
                ZStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 64, height: 64)
                        .shadow(color: .red.opacity(0.4), radius: 8, y: 2)

                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .help("Start recording (or use global hotkey)")

            // Last meeting summary
            if let lastMeeting = appState.currentMeeting,
               lastMeeting.status == .ready || lastMeeting.status == .synced {
                lastMeetingSummary(meeting: lastMeeting)
            }
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 16) {
            // Elapsed time
            Text(formatDuration(recordingService.currentDuration))
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(.red)

            // Waveform animation placeholder
            waveformPlaceholder
                .frame(height: 40)

            // Control buttons
            HStack(spacing: 24) {
                // Pause / Resume button
                Button(action: togglePause) {
                    VStack(spacing: 4) {
                        Image(systemName: recordingService.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text(recordingService.isPaused ? "Resume" : "Pause")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // Stop button
                Button(action: stopRecording) {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(.red)
                                .frame(width: 44, height: 44)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.white)
                                .frame(width: 18, height: 18)
                        }
                        Text("Stop")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if recordingService.isPaused {
                Text("Recording Paused")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Transcribing View

    private var transcribingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.blue)

            Text("Transcribing audio...")
                .font(.headline)

            ProgressView(value: appState.transcriptionProgress, total: 1.0)
                .progressViewStyle(.linear)

            Text("\(Int(appState.transcriptionProgress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                cancelTranscription()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Generating summary...")
                .font(.headline)

            Text("Extracting action items and key decisions")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Syncing View

    private var syncingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.green)

            Text("Syncing to Notion...")
                .font(.headline)

            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Waveform Placeholder

    private var waveformPlaceholder: some View {
        HStack(spacing: 3) {
            ForEach(0..<20, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(.red.opacity(recordingService.isPaused ? 0.3 : 0.7))
                    .frame(width: 4, height: waveformBarHeight(index: index))
                    .animation(
                        recordingService.isPaused
                            ? .none
                            : .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.05),
                        value: recordingService.isPaused
                    )
            }
        }
    }

    // MARK: - Last Meeting Summary

    private func lastMeetingSummary(meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Text("Last Meeting")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(meeting.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if let summary = meeting.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                appState.lastError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.1))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func startRecording() {
        do {
            let deviceID = settings.selectedAudioDeviceID
            try recordingService.startRecording(deviceID: deviceID)
            appState.mode = .recording
            appState.statusMessage = "Recording"
            appState.lastError = nil
        } catch {
            appState.lastError = error.localizedDescription
        }
    }

    private func stopRecording() {
        guard let result = recordingService.stopRecording() else {
            appState.lastError = "No recording data available."
            appState.mode = .idle
            return
        }

        let audioURL = result.url
        let duration = result.duration
        appState.mode = .transcribing
        appState.statusMessage = "Transcribing..."

        // Create the meeting record
        var meeting = MeetingRecord(
            title: "Meeting \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short))",
            date: Date(),
            duration: duration
        )
        meeting.audioFilePath = audioURL.path
        meeting.status = .transcribing
        appState.currentMeeting = meeting

        // Begin transcription
        Task {
            await transcribeAndProcess(audioURL: audioURL)
        }
    }

    private func togglePause() {
        if recordingService.isPaused {
            recordingService.resumeRecording()
        } else {
            recordingService.pauseRecording()
        }
    }

    private func transcribeAndProcess(audioURL: URL) async {
        do {
            // Step 1: Transcribe
            let transcript = try await whisperService.transcribe(
                audioURL: audioURL,
                model: settings.whisperModelSize,
                language: settings.whisperLanguage
            )

            appState.currentMeeting?.transcript = transcript
            appState.currentMeeting?.status = .processing
            appState.mode = .processing
            appState.statusMessage = "Processing..."

            // Step 2: Post-processing (summarization) would go here
            // For now, mark as ready and show preview
            appState.currentMeeting?.status = .ready
            appState.mode = .idle
            appState.statusMessage = "Ready"
            appState.showMeetingPreview = true

        } catch {
            appState.lastError = "Transcription failed: \(error.localizedDescription)"
            appState.currentMeeting?.status = .failed
            appState.mode = .idle
            appState.statusMessage = "Ready"
        }
    }

    private func cancelTranscription() {
        // Reset state on cancellation
        appState.mode = .idle
        appState.statusMessage = "Ready"
        appState.transcriptionProgress = 0
    }

    private func openSettings() {
        // Bring the app to front so the settings window is visible
        NSApp.activate(ignoringOtherApps: true)

        // macOS 14+ uses showSettingsWindow:, macOS 13 uses showPreferencesWindow:
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func waveformBarHeight(index: Int) -> CGFloat {
        if recordingService.isPaused {
            return 6
        }
        // Simulated varying heights for visual effect
        let heights: [CGFloat] = [12, 20, 8, 28, 16, 32, 10, 24, 18, 36,
                                   14, 30, 8, 22, 26, 34, 12, 20, 16, 28]
        return heights[index % heights.count]
    }
}
