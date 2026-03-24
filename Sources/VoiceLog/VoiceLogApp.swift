import SwiftUI

@main
struct VoiceLogApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var recordingService = AudioRecordingService()
    @StateObject private var systemAudioService = SystemAudioCaptureService()
    @StateObject private var whisperService = WhisperService()
    @StateObject private var notionService = NotionService()
    @StateObject private var hotkeyService = HotkeyService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(settings)
                .environmentObject(recordingService)
                .environmentObject(systemAudioService)
                .environmentObject(whisperService)
                .environmentObject(notionService)
        } label: {
            Label {
                Text(appState.menuBarTitle)
            } icon: {
                Image(systemName: appState.menuBarIcon)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(appState.mode == .recording ? .red : .primary)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(notionService)
        }
    }

    init() {
        // Register global hotkey on app launch
    }
}
