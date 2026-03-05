import Testing
import Foundation
import GRDB
@testable import VoiceLog

@Suite("DatabaseService Tests")
struct DatabaseServiceTests {

    private func makeTestDatabase() throws -> DatabaseService {
        let dbQueue = try DatabaseQueue()
        return try DatabaseService(dbQueue: dbQueue)
    }

    @Test("Save and fetch meeting")
    func saveAndFetch() throws {
        let db = try makeTestDatabase()
        var meeting = MeetingRecord(title: "Test Meeting", duration: 600)
        meeting.transcript = "Hello world"
        meeting.summary = "A test meeting"
        meeting.actionItems = ["Task 1", "Task 2"]
        meeting.keyDecisions = ["Go with plan A"]
        meeting.status = .ready

        try db.saveMeeting(&meeting)

        let fetched = try db.fetchMeeting(byId: meeting.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Meeting")
        #expect(fetched?.duration == 600)
        #expect(fetched?.transcript == "Hello world")
        #expect(fetched?.summary == "A test meeting")
        #expect(fetched?.actionItems == ["Task 1", "Task 2"])
        #expect(fetched?.keyDecisions == ["Go with plan A"])
        #expect(fetched?.status == .ready)
    }

    @Test("Fetch all meetings ordered by date")
    func fetchAll() throws {
        let db = try makeTestDatabase()
        var m1 = MeetingRecord(title: "First", date: Date(timeIntervalSince1970: 1000))
        var m2 = MeetingRecord(title: "Second", date: Date(timeIntervalSince1970: 2000))

        try db.saveMeeting(&m1)
        try db.saveMeeting(&m2)

        let all = try db.fetchAllMeetings()
        #expect(all.count == 2)
        #expect(all[0].title == "Second") // newest first
        #expect(all[1].title == "First")
    }

    @Test("Fetch pending sync meetings")
    func fetchPendingSync() throws {
        let db = try makeTestDatabase()
        var m1 = MeetingRecord(title: "Ready Pending")
        m1.status = .ready
        m1.notionSyncStatus = .pending

        var m2 = MeetingRecord(title: "Ready Synced")
        m2.status = .ready
        m2.notionSyncStatus = .synced

        var m3 = MeetingRecord(title: "Ready Queued")
        m3.status = .ready
        m3.notionSyncStatus = .queued

        try db.saveMeeting(&m1)
        try db.saveMeeting(&m2)
        try db.saveMeeting(&m3)

        let pending = try db.fetchPendingSyncMeetings()
        #expect(pending.count == 2)
    }

    @Test("Update meeting")
    func updateMeeting() throws {
        let db = try makeTestDatabase()
        var meeting = MeetingRecord(title: "Original")
        try db.saveMeeting(&meeting)

        meeting.title = "Updated"
        meeting.summary = "New summary"
        try db.updateMeeting(&meeting)

        let fetched = try db.fetchMeeting(byId: meeting.id)
        #expect(fetched?.title == "Updated")
        #expect(fetched?.summary == "New summary")
    }

    @Test("Delete meeting")
    func deleteMeeting() throws {
        let db = try makeTestDatabase()
        var meeting = MeetingRecord(title: "To Delete")
        try db.saveMeeting(&meeting)

        #expect(try db.fetchMeeting(byId: meeting.id) != nil)

        try db.deleteMeeting(byId: meeting.id)
        #expect(try db.fetchMeeting(byId: meeting.id) == nil)
    }

    @Test("Meeting count")
    func meetingCount() throws {
        let db = try makeTestDatabase()
        #expect(try db.meetingCount() == 0)

        var m1 = MeetingRecord(title: "One")
        var m2 = MeetingRecord(title: "Two")
        try db.saveMeeting(&m1)
        try db.saveMeeting(&m2)

        #expect(try db.meetingCount() == 2)
    }

    @Test("Delete old meetings")
    func deleteOldMeetings() throws {
        let db = try makeTestDatabase()
        var old = MeetingRecord(title: "Old", date: Date(timeIntervalSinceNow: -100 * 86400))
        var recent = MeetingRecord(title: "Recent", date: Date())

        try db.saveMeeting(&old)
        try db.saveMeeting(&recent)

        try db.deleteOldMeetings(olderThanDays: 30)

        let all = try db.fetchAllMeetings()
        #expect(all.count == 1)
        #expect(all[0].title == "Recent")
    }

    @Test("Save meeting with nil arrays")
    func saveNilArrays() throws {
        let db = try makeTestDatabase()
        var meeting = MeetingRecord(title: "No Items")

        try db.saveMeeting(&meeting)

        let fetched = try db.fetchMeeting(byId: meeting.id)
        #expect(fetched?.actionItems == nil)
        #expect(fetched?.keyDecisions == nil)
    }
}
