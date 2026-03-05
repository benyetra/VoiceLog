import SwiftUI

// MARK: - MeetingPreviewView

struct MeetingPreviewView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notionService: NotionService

    @State private var editableTitle: String = ""
    @State private var isSyncing: Bool = false
    @State private var syncError: String?
    @State private var savedLocally: Bool = false

    var body: some View {
        if let meeting = appState.currentMeeting {
            VStack(alignment: .leading, spacing: 12) {
                // Section header
                HStack {
                    Text("Meeting Preview")
                        .font(.headline)
                    Spacer()
                    Button {
                        appState.showMeetingPreview = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Editable title
                TextField("Meeting Title", text: $editableTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onAppear {
                        editableTitle = meeting.title
                    }

                // Date and duration
                HStack(spacing: 16) {
                    Label {
                        Text(meeting.date, style: .date)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label {
                        Text(formatDuration(meeting.duration))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Spacer()
                }

                Divider()

                // Summary
                if let summary = meeting.summary {
                    summarySection(summary: summary)
                }

                // Action Items
                if let actionItems = meeting.actionItems, !actionItems.isEmpty {
                    actionItemsSection(items: actionItems)
                }

                // Key Decisions
                if let keyDecisions = meeting.keyDecisions, !keyDecisions.isEmpty {
                    keyDecisionsSection(decisions: keyDecisions)
                }

                // Transcript snippet
                if let transcript = meeting.transcript {
                    transcriptSection(transcript: transcript)
                }

                Divider()

                // Error display
                if let error = syncError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    // Sync to Notion
                    Button(action: syncToNotion) {
                        HStack(spacing: 6) {
                            if isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Sync to Notion")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isSyncing || !notionService.isConnected)
                    .help(notionService.isConnected
                          ? "Send this meeting to your Notion workspace"
                          : "Connect Notion in Settings first")

                    // Save Locally
                    Button(action: saveLocally) {
                        HStack(spacing: 6) {
                            Image(systemName: savedLocally ? "checkmark.circle.fill" : "square.and.arrow.down")
                            Text(savedLocally ? "Saved" : "Save Locally")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(savedLocally)
                }
            }
        } else {
            Text("No meeting data available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sections

    private func summarySection(summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Summary", systemImage: "doc.text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func actionItemsSection(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Action Items", systemImage: "checklist")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 6))
                            .foregroundStyle(Color.accentColor)
                            .padding(.top, 4)
                        Text(item)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func keyDecisionsSection(decisions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Key Decisions", systemImage: "lightbulb")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(decisions, id: \.self) { decision in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.orange)
                            .padding(.top, 4)
                        Text(decision)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func transcriptSection(transcript: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Transcript", systemImage: "text.quote")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Text(transcript)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Actions

    private func syncToNotion() {
        guard let meeting = appState.currentMeeting else { return }
        guard let databaseId = AppSettings.shared.notionDatabaseId else {
            syncError = "No Notion database selected. Configure in Settings."
            return
        }

        isSyncing = true
        syncError = nil

        // Update title before sync
        var updatedMeeting = meeting
        updatedMeeting.title = editableTitle

        appState.mode = .syncing
        appState.statusMessage = "Syncing..."

        Task {
            do {
                _ = try await notionService.createMeetingPage(
                    meeting: updatedMeeting,
                    databaseId: databaseId
                )
                appState.currentMeeting?.notionSyncStatus = .synced
                appState.currentMeeting?.status = .synced
                appState.showMeetingPreview = false
                appState.mode = .idle
                appState.statusMessage = "Ready"
            } catch {
                syncError = error.localizedDescription
                appState.mode = .idle
                appState.statusMessage = "Ready"
            }
            isSyncing = false
        }
    }

    private func saveLocally() {
        // Update title
        appState.currentMeeting?.title = editableTitle
        appState.currentMeeting?.status = .ready
        savedLocally = true

        // Persist to local database would happen here via DatabaseService
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        }
        return String(format: "%dm %ds", minutes, seconds)
    }
}
