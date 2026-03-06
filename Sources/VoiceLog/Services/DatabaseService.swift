import Foundation
import GRDB

// MARK: - DatabaseService

/// Manages the SQLite database via GRDB for persisting meeting records.
final class DatabaseService {
    static let shared = DatabaseService()

    private let dbQueue: DatabaseQueue

    // MARK: - Initialization

    private init() {
        do {
            let fileManager = FileManager.default
            let directoryURL = URL(fileURLWithPath: AppSettings.shared.localStoragePath, isDirectory: true)

            // Create directory if it does not exist
            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }

            let dbPath = directoryURL.appendingPathComponent("voicelog.db").path
            dbQueue = try DatabaseQueue(path: dbPath)
            try migrator.migrate(dbQueue)
        } catch {
            fatalError("DatabaseService: Failed to initialize database: \(error)")
        }
    }

    /// Designated initializer for testing or custom database locations.
    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
    }

    // MARK: - Migrations

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createMeetingRecords") { db in
            try db.create(table: "meeting_records") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull().defaults(to: "Untitled Meeting")
                t.column("date", .datetime).notNull()
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("audioFilePath", .text)
                t.column("transcript", .text)
                t.column("summary", .text)
                t.column("actionItems", .text) // JSON-encoded [String]
                t.column("keyDecisions", .text) // JSON-encoded [String]
                t.column("whisperModel", .text).notNull().defaults(to: "medium")
                t.column("status", .text).notNull().defaults(to: "recording")
                t.column("notionPageId", .text)
                t.column("notionSyncStatus", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        return migrator
    }

    // MARK: - Create / Update

    /// Saves a new meeting record or updates an existing one.
    func saveMeeting(_ meeting: inout MeetingRecord) throws {
        meeting.updatedAt = Date()
        try dbQueue.write { db in
            try meeting.save(db)
        }
    }

    /// Updates an existing meeting record in the database.
    func updateMeeting(_ meeting: inout MeetingRecord) throws {
        meeting.updatedAt = Date()
        try dbQueue.write { db in
            try meeting.update(db)
        }
    }

    // MARK: - Read

    /// Fetches a single meeting record by its UUID.
    func fetchMeeting(byId id: UUID) throws -> MeetingRecord? {
        try dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: id)
        }
    }

    /// Fetches all meeting records, ordered by date descending (most recent first).
    func fetchAllMeetings() throws -> [MeetingRecord] {
        try dbQueue.read { db in
            try MeetingRecord
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    /// Fetches meetings that have not yet been synced to Notion.
    func fetchPendingSyncMeetings() throws -> [MeetingRecord] {
        try dbQueue.read { db in
            try MeetingRecord
                .filter(Column("notionSyncStatus") == SyncStatus.pending.rawValue
                    || Column("notionSyncStatus") == SyncStatus.queued.rawValue)
                .filter(Column("status") == RecordStatus.ready.rawValue)
                .order(Column("date").asc)
                .fetchAll(db)
        }
    }

    /// Fetches meetings filtered by status.
    func fetchMeetings(withStatus status: RecordStatus) throws -> [MeetingRecord] {
        try dbQueue.read { db in
            try MeetingRecord
                .filter(Column("status") == status.rawValue)
                .order(Column("date").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Delete

    /// Deletes a meeting record by its UUID. Returns true if a record was deleted.
    @discardableResult
    func deleteMeeting(byId id: UUID) throws -> Bool {
        try dbQueue.write { db in
            try MeetingRecord.deleteOne(db, key: id)
        }
    }

    /// Deletes meetings older than the specified number of days.
    /// Returns the count of deleted records.
    @discardableResult
    func deleteOldMeetings(olderThanDays days: Int) throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return try dbQueue.write { db in
            try MeetingRecord
                .filter(Column("date") < cutoffDate)
                .deleteAll(db)
        }
    }

    // MARK: - Statistics

    /// Returns the total number of meeting records in the database.
    func meetingCount() throws -> Int {
        try dbQueue.read { db in
            try MeetingRecord.fetchCount(db)
        }
    }
}
