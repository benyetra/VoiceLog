import Foundation
import GRDB

// MARK: - MeetingRecord

/// Represents a single meeting recording session.
/// Array fields (actionItems, keyDecisions) are stored as JSON strings in SQLite.
struct MeetingRecord: Codable, Identifiable {
    var id: UUID
    var title: String
    var date: Date
    var duration: TimeInterval // seconds
    var audioFilePath: String?
    var transcript: String?
    var summary: String?
    var actionItems: [String]?
    var keyDecisions: [String]?
    var whisperModel: WhisperModelSize
    var status: RecordStatus
    var notionPageId: String?
    var notionSyncStatus: SyncStatus
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "meeting_records"

    init(
        id: UUID = UUID(),
        title: String = "Untitled Meeting",
        date: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.duration = duration
        self.whisperModel = .medium
        self.status = .recording
        self.notionSyncStatus = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - FetchableRecord

extension MeetingRecord: FetchableRecord {
    init(row: Row) {
        id = row["id"]
        title = row["title"]
        date = row["date"]
        duration = row["duration"]
        audioFilePath = row["audioFilePath"]
        transcript = row["transcript"]
        summary = row["summary"]
        whisperModel = row["whisperModel"]
        status = row["status"]
        notionPageId = row["notionPageId"]
        notionSyncStatus = row["notionSyncStatus"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]

        // Decode JSON-encoded array fields
        if let jsonString: String = row["actionItems"],
           let data = jsonString.data(using: .utf8) {
            actionItems = try? JSONDecoder().decode([String].self, from: data)
        } else {
            actionItems = nil
        }

        if let jsonString: String = row["keyDecisions"],
           let data = jsonString.data(using: .utf8) {
            keyDecisions = try? JSONDecoder().decode([String].self, from: data)
        } else {
            keyDecisions = nil
        }
    }
}

// MARK: - PersistableRecord

extension MeetingRecord: PersistableRecord {
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["date"] = date
        container["duration"] = duration
        container["audioFilePath"] = audioFilePath
        container["transcript"] = transcript
        container["summary"] = summary
        container["whisperModel"] = whisperModel
        container["status"] = status
        container["notionPageId"] = notionPageId
        container["notionSyncStatus"] = notionSyncStatus
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt

        // Encode array fields as JSON strings for SQLite storage
        if let items = actionItems,
           let data = try? JSONEncoder().encode(items),
           let jsonString = String(data: data, encoding: .utf8) {
            container["actionItems"] = jsonString
        } else {
            container["actionItems"] = nil as String?
        }

        if let decisions = keyDecisions,
           let data = try? JSONEncoder().encode(decisions),
           let jsonString = String(data: data, encoding: .utf8) {
            container["keyDecisions"] = jsonString
        } else {
            container["keyDecisions"] = nil as String?
        }
    }
}

// MARK: - TableRecord

extension MeetingRecord: TableRecord {}

// MARK: - RecordStatus

enum RecordStatus: String, Codable, DatabaseValueConvertible {
    case recording
    case transcribing
    case processing
    case ready
    case synced
    case failed
}

// MARK: - SyncStatus

enum SyncStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case syncing
    case synced
    case failed
    case queued // offline retry
}

// MARK: - WhisperModelSize

enum WhisperModelSize: String, Codable, CaseIterable, DatabaseValueConvertible {
    case tiny
    case base
    case small
    case medium
    case large

    var displayName: String {
        rawValue.capitalized
    }

    var diskSize: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~142 MB"
        case .small: return "~466 MB"
        case .medium: return "~1.5 GB"
        case .large: return "~2.9 GB"
        }
    }

    var estimatedSpeed: String {
        switch self {
        case .tiny: return "~10x real-time"
        case .base: return "~7x real-time"
        case .small: return "~4x real-time"
        case .medium: return "~2x real-time"
        case .large: return "~1x real-time"
        }
    }
}
