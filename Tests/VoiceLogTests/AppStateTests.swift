import Testing
import Foundation
@testable import VoiceLog

@Suite("AppState Tests")
struct AppStateTests {

    @MainActor
    @Test("Default state is idle")
    func defaultState() {
        let state = AppState()
        #expect(state.mode == .idle)
        #expect(state.recordingDuration == 0)
        #expect(state.transcriptionProgress == 0)
        #expect(state.currentMeeting == nil)
        #expect(state.showMeetingPreview == false)
        #expect(state.lastError == nil)
        #expect(state.statusMessage == "Ready")
    }

    @MainActor
    @Test("Menu bar icon changes with mode")
    func menuBarIcon() {
        let state = AppState()

        state.mode = .idle
        #expect(state.menuBarIcon == "mic.circle")

        state.mode = .recording
        #expect(state.menuBarIcon == "mic.circle.fill")

        state.mode = .transcribing
        #expect(state.menuBarIcon == "text.bubble")

        state.mode = .processing
        #expect(state.menuBarIcon == "brain")

        state.mode = .syncing
        #expect(state.menuBarIcon == "arrow.triangle.2.circlepath")
    }

    @MainActor
    @Test("Menu bar title shows duration when recording")
    func menuBarTitleRecording() {
        let state = AppState()
        state.mode = .recording
        state.recordingDuration = 125 // 2:05

        #expect(state.menuBarTitle == "2:05")
    }

    @MainActor
    @Test("Menu bar title empty when idle")
    func menuBarTitleIdle() {
        let state = AppState()
        state.mode = .idle
        #expect(state.menuBarTitle == "")
    }

    @MainActor
    @Test("Menu bar title shows status text for non-recording modes")
    func menuBarTitleOtherModes() {
        let state = AppState()

        state.mode = .transcribing
        #expect(state.menuBarTitle == "Transcribing...")

        state.mode = .processing
        #expect(state.menuBarTitle == "Processing...")

        state.mode = .syncing
        #expect(state.menuBarTitle == "Syncing...")
    }

    @MainActor
    @Test("AppMode raw values")
    func appModeRawValues() {
        #expect(AppMode.idle.rawValue == "idle")
        #expect(AppMode.recording.rawValue == "recording")
        #expect(AppMode.transcribing.rawValue == "transcribing")
        #expect(AppMode.processing.rawValue == "processing")
        #expect(AppMode.syncing.rawValue == "syncing")
    }
}
