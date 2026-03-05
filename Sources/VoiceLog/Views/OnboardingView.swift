import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notionService: NotionService

    @State private var currentStep: Int = 0
    @State private var selectedDatabaseId: String?
    @State private var newDatabaseName: String = "VoiceLog Meetings"
    @State private var isCreatingDatabase: Bool = false
    @State private var databases: [NotionDatabase] = []
    @State private var isLoadingDatabases: Bool = false
    @State private var errorMessage: String?

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    notionDatabaseStep
                case 2:
                    whisperModelStep
                case 3:
                    hotkeyStep
                case 4:
                    doneStep
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)

            Divider()

            // Navigation footer
            HStack {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                // Navigation buttons
                HStack(spacing: 12) {
                    if currentStep > 0 && currentStep < totalSteps - 1 {
                        Button("Back") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                        .controlSize(.regular)
                    }

                    if currentStep < totalSteps - 1 {
                        Button(currentStep == 0 ? "Get Started" : "Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 440)
    }

    // MARK: - Step 1: Welcome + Connect Notion

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to VoiceLog")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Record meetings, transcribe with Whisper, and sync everything to Notion -- all from your menu bar.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 12) {
                Text("Connect your Notion workspace to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if notionService.isConnected {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected to \(notionService.workspaceName ?? "Notion")")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    Button(action: {
                        notionService.startOAuth()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                            Text("Connect Notion")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Button("Skip for now") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Step 2: Select / Create Notion Database

    private var notionDatabaseStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "tablecells")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Choose a Database")
                .font(.title)
                .fontWeight(.bold)

            Text("Select an existing Notion database for your meeting notes, or create a new one with the correct schema.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            if notionService.isConnected {
                VStack(spacing: 12) {
                    // Existing databases
                    Picker("Database", selection: Binding(
                        get: { selectedDatabaseId ?? "" },
                        set: { selectedDatabaseId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Select a database...").tag("")
                        ForEach(databases, id: \.id) { db in
                            Text(db.title).tag(db.id)
                        }
                    }
                    .frame(maxWidth: 300)

                    HStack {
                        Button(action: loadDatabases) {
                            if isLoadingDatabases {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isLoadingDatabases)
                    }

                    Divider()

                    Text("Or create a new database:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: createNewDatabase) {
                        if isCreatingDatabase {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Create VoiceLog Database", systemImage: "plus.circle")
                        }
                    }
                    .controlSize(.regular)
                    .disabled(isCreatingDatabase)

                    if let dbId = selectedDatabaseId {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Database selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onAppear {
                            settings.notionDatabaseId = dbId
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("Connect Notion first to select a database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            if notionService.isConnected {
                loadDatabases()
            }
        }
    }

    // MARK: - Step 3: Choose Whisper Model

    private var whisperModelStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Transcription Model")
                .font(.title)
                .fontWeight(.bold)

            Text("Choose a Whisper model based on your needs. Larger models are more accurate but slower and use more disk space.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 4) {
                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    modelRow(model: model)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func modelRow(model: WhisperModelSize) -> some View {
        Button(action: {
            settings.whisperModelSize = model
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("\(model.diskSize) -- \(model.estimatedSpeed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if settings.whisperModelSize == model {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.whisperModelSize == model
                          ? Color.accentColor.opacity(0.1)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.whisperModelSize == model
                            ? Color.accentColor.opacity(0.3)
                            : Color.secondary.opacity(0.15),
                            lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: Set Global Hotkey

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Global Hotkey")
                .font(.title)
                .fontWeight(.bold)

            Text("Set a keyboard shortcut to start and stop recording from anywhere in macOS.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(spacing: 12) {
                Text("Current Hotkey")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(settings.globalHotkey)
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button("Change Hotkey") {
                    // Hotkey recording placeholder
                    // In production, this would open a key capture view
                }
                .controlSize(.small)

                Text("You can change this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 5: Done

    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("VoiceLog is ready to use. Click the menu bar icon or press your hotkey to start recording.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 8) {
                setupSummaryRow(
                    icon: "doc.text",
                    label: "Notion",
                    value: notionService.isConnected
                        ? (notionService.workspaceName ?? "Connected")
                        : "Not connected"
                )
                setupSummaryRow(
                    icon: "waveform",
                    label: "Whisper Model",
                    value: settings.whisperModelSize.displayName
                )
                setupSummaryRow(
                    icon: "keyboard",
                    label: "Hotkey",
                    value: settings.globalHotkey
                )
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button(action: completeOnboarding) {
                Text("Start Using VoiceLog")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func setupSummaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    // MARK: - Actions

    private func loadDatabases() {
        isLoadingDatabases = true
        errorMessage = nil
        Task {
            do {
                databases = try await notionService.listDatabases()
                isLoadingDatabases = false
            } catch {
                errorMessage = error.localizedDescription
                isLoadingDatabases = false
            }
        }
    }

    private func createNewDatabase() {
        isCreatingDatabase = true
        errorMessage = nil
        Task {
            do {
                let dbId = try await notionService.createMeetingDatabase(parentPageId: nil)
                selectedDatabaseId = dbId
                settings.notionDatabaseId = dbId
                isCreatingDatabase = false
                loadDatabases()
            } catch {
                errorMessage = error.localizedDescription
                isCreatingDatabase = false
            }
        }
    }

    private func completeOnboarding() {
        appState.isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}
