import SwiftUI

// MARK: - AppMode

enum AppMode: String {
    case idle
    case recording
    case transcribing
    case processing
    case syncing
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .idle
    @Published var recordingDuration: TimeInterval = 0
    @Published var transcriptionProgress: Double = 0
    @Published var currentMeeting: MeetingRecord?
    @Published var isOnboardingComplete: Bool
    @Published var showMeetingPreview: Bool = false
    @Published var lastError: String?
    @Published var statusMessage: String = "Ready"

    init() {
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    }

    var menuBarIcon: String {
        switch mode {
        case .idle: return "mic.circle"
        case .recording: return "mic.circle.fill"
        case .transcribing: return "text.bubble"
        case .processing: return "brain"
        case .syncing: return "arrow.triangle.2.circlepath"
        }
    }

    var menuBarTitle: String {
        switch mode {
        case .idle: return ""
        case .recording: return formatDuration(recordingDuration)
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        case .syncing: return "Syncing..."
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
