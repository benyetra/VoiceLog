import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notionService: NotionService

    private enum SettingsTab: Hashable {
        case general
        case audio
        case transcription
        case ai
        case notion
        case hotkey
    }

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            AudioSettingsTab(settings: settings)
                .tabItem {
                    Label("Audio", systemImage: "mic")
                }
                .tag(SettingsTab.audio)

            TranscriptionSettingsTab(settings: settings)
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(SettingsTab.transcription)

            AISettingsTab(settings: settings)
                .tabItem {
                    Label("AI", systemImage: "brain")
                }
                .tag(SettingsTab.ai)

            NotionSettingsTab(settings: settings, notionService: notionService)
                .tabItem {
                    Label("Notion", systemImage: "doc.text")
                }
                .tag(SettingsTab.notion)

            HotkeySettingsTab(settings: settings)
                .tabItem {
                    Label("Hotkey", systemImage: "keyboard")
                }
                .tag(SettingsTab.hotkey)
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)

                HStack {
                    Text("Local storage path")
                    Spacer()
                    Text(settings.localStoragePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .trailing)

                    Button("Change...") {
                        selectStoragePath()
                    }
                    .controlSize(.small)
                }

                Picker("Retention period", selection: $settings.retentionDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func selectStoragePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select Storage Folder"

        if panel.runModal() == .OK, let url = panel.url {
            settings.localStoragePath = url.path
        }
    }
}

// MARK: - Audio Settings Tab

private struct AudioSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var availableDevices: [AudioInputDevice] = []
    @State private var isTestingRecording: Bool = false

    var body: some View {
        Form {
            Section {
                Picker("Input device", selection: Binding(
                    get: { settings.selectedAudioDeviceID ?? "" },
                    set: { settings.selectedAudioDeviceID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default").tag("")
                    ForEach(availableDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }

                Button(action: refreshDevices) {
                    Label("Refresh Devices", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            } header: {
                Text("Audio Input")
            }

            Section {
                HStack {
                    Button(action: toggleTestRecording) {
                        Label(
                            isTestingRecording ? "Stop Test" : "Test Recording",
                            systemImage: isTestingRecording ? "stop.circle" : "play.circle"
                        )
                    }
                    .controlSize(.small)

                    if isTestingRecording {
                        ProgressView()
                            .controlSize(.small)
                        Text("Recording test audio...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Test")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshDevices()
        }
    }

    private func refreshDevices() {
        availableDevices = AudioRecordingService.listInputDevices()
    }

    private func toggleTestRecording() {
        isTestingRecording.toggle()
        // Actual test recording logic would be wired here
        if isTestingRecording {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                isTestingRecording = false
            }
        }
    }
}

// MARK: - Transcription Settings Tab

private struct TranscriptionSettingsTab: View {
    @ObservedObject var settings: AppSettings

    private let languages: [(String, String?)] = [
        ("Auto-detect", nil),
        ("English", "en"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Japanese", "ja"),
        ("Chinese", "zh"),
        ("Korean", "ko"),
        ("Russian", "ru"),
        ("Arabic", "ar"),
        ("Hindi", "hi"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Whisper model", selection: $settings.whisperModelSize) {
                    ForEach(WhisperModelSize.allCases, id: \.self) { model in
                        HStack {
                            Text(model.displayName)
                            Spacer()
                            Text("\(model.diskSize) -- \(model.estimatedSpeed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(model)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Info")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("Selected: \(settings.whisperModelSize.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Size: \(settings.whisperModelSize.diskSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Speed: \(settings.whisperModelSize.estimatedSpeed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Whisper Model")
            }

            Section {
                Picker("Language", selection: Binding(
                    get: { settings.whisperLanguage ?? "" },
                    set: { settings.whisperLanguage = $0.isEmpty ? nil : $0 }
                )) {
                    ForEach(languages, id: \.0) { language in
                        Text(language.0).tag(language.1 ?? "")
                    }
                }
            } header: {
                Text("Language Override")
            } footer: {
                Text("Leave on Auto-detect unless Whisper consistently misidentifies the language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - AI Settings Tab

private struct AISettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var apiKeyInput: String = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI post-processing", isOn: $settings.aiPostProcessingEnabled)

                Text("When enabled, VoiceLog will generate summaries, extract action items, and identify key decisions from your transcripts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Processing")
            }

            if settings.aiPostProcessingEnabled {
                Section {
                    Picker("LLM Provider", selection: $settings.useLocalLLM) {
                        Text("Local (Ollama)").tag(true)
                        Text("Cloud (OpenAI)").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Provider")
                }

                if settings.useLocalLLM {
                    Section {
                        TextField("Ollama model name", text: $settings.ollamaModel)
                            .textFieldStyle(.roundedBorder)

                        Text("Ensure Ollama is running locally. Common models: llama3, mistral, phi3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Ollama Configuration")
                    }
                } else {
                    Section {
                        HStack {
                            SecureField("API Key", text: $apiKeyInput)
                                .textFieldStyle(.roundedBorder)

                            Button("Save") {
                                settings.openAIApiKey = apiKeyInput
                                apiKeyInput = ""
                            }
                            .controlSize(.small)
                            .disabled(apiKeyInput.isEmpty)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: settings.openAIApiKey != nil
                                  ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(settings.openAIApiKey != nil ? .green : .red)
                            Text(settings.openAIApiKey != nil
                                 ? "API key is configured"
                                 : "No API key set")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("OpenAI Configuration")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Notion Settings Tab

private struct NotionSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notionService: NotionService

    @State private var databases: [NotionDatabase] = []
    @State private var isLoadingDatabases: Bool = false
    @State private var parentPageId: String = ""
    @State private var isCreatingDatabase: Bool = false
    @State private var notionError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    if notionService.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Connected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let workspace = notionService.workspaceName {
                                Text(workspace)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Disconnect") {
                            // Disconnect logic placeholder
                        }
                        .controlSize(.small)
                    } else {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                        Text("Not connected")
                            .font(.subheadline)
                        Spacer()
                        Button("Connect to Notion") {
                            notionService.startOAuth()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Workspace")
            }

            if notionService.isConnected {
                Section {
                    HStack {
                        Picker("Database", selection: Binding(
                            get: { settings.notionDatabaseId ?? "" },
                            set: { settings.notionDatabaseId = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Select a database...").tag("")
                            ForEach(databases, id: \.id) { db in
                                Text(db.title).tag(db.id)
                            }
                        }

                        Button(action: loadDatabases) {
                            if isLoadingDatabases {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isLoadingDatabases)
                    }
                } header: {
                    Text("Meeting Database")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Automatically create a VoiceLog database with the correct schema in your Notion workspace.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Parent page ID (optional)", text: $parentPageId)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)

                            Button(action: createDatabase) {
                                if isCreatingDatabase {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Create Database")
                                }
                            }
                            .controlSize(.small)
                            .disabled(isCreatingDatabase)
                        }
                    }
                } header: {
                    Text("Auto Schema")
                }

                if let error = notionError {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            if notionService.isConnected {
                loadDatabases()
            }
        }
    }

    private func loadDatabases() {
        isLoadingDatabases = true
        notionError = nil
        Task {
            do {
                let dbs = try await notionService.listDatabases()
                databases = dbs
                isLoadingDatabases = false
            } catch {
                notionError = error.localizedDescription
                isLoadingDatabases = false
            }
        }
    }

    private func createDatabase() {
        isCreatingDatabase = true
        notionError = nil
        let pageId = parentPageId.isEmpty ? nil : parentPageId
        Task {
            do {
                let newDbId = try await notionService.createMeetingDatabase(parentPageId: pageId)
                settings.notionDatabaseId = newDbId
                isCreatingDatabase = false
                loadDatabases()
            } catch {
                notionError = error.localizedDescription
                isCreatingDatabase = false
            }
        }
    }
}

// MARK: - Hotkey Settings Tab

private struct HotkeySettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var isRecordingHotkey: Bool = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Global Hotkey")
                    Spacer()
                    Text(settings.globalHotkey)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecordingHotkey ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }

                Button(action: {
                    isRecordingHotkey.toggle()
                }) {
                    Text(isRecordingHotkey ? "Press desired key combination..." : "Change Hotkey")
                }
                .controlSize(.small)

                if isRecordingHotkey {
                    Text("Press your desired key combination, then click away to confirm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("This hotkey toggles recording from anywhere in macOS. The default is Control+Option+R.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
