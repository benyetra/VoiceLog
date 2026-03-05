import Testing
import Foundation
@testable import VoiceLog

@Suite("MeetingRecord Tests")
struct MeetingRecordTests {

    @Test("Default initialization")
    func defaultInit() {
        let record = MeetingRecord()
        #expect(record.title == "Untitled Meeting")
        #expect(record.duration == 0)
        #expect(record.whisperModel == .medium)
        #expect(record.status == .recording)
        #expect(record.notionSyncStatus == .pending)
        #expect(record.transcript == nil)
        #expect(record.summary == nil)
        #expect(record.actionItems == nil)
        #expect(record.keyDecisions == nil)
        #expect(record.audioFilePath == nil)
        #expect(record.notionPageId == nil)
    }

    @Test("Custom initialization")
    func customInit() {
        let date = Date()
        let record = MeetingRecord(
            title: "Sprint Planning",
            date: date,
            duration: 1800
        )
        #expect(record.title == "Sprint Planning")
        #expect(record.date == date)
        #expect(record.duration == 1800)
    }

    @Test("ID is unique")
    func uniqueIds() {
        let r1 = MeetingRecord()
        let r2 = MeetingRecord()
        #expect(r1.id != r2.id)
    }

    @Test("RecordStatus raw values")
    func recordStatusRawValues() {
        #expect(RecordStatus.recording.rawValue == "recording")
        #expect(RecordStatus.transcribing.rawValue == "transcribing")
        #expect(RecordStatus.processing.rawValue == "processing")
        #expect(RecordStatus.ready.rawValue == "ready")
        #expect(RecordStatus.synced.rawValue == "synced")
        #expect(RecordStatus.failed.rawValue == "failed")
    }

    @Test("SyncStatus raw values")
    func syncStatusRawValues() {
        #expect(SyncStatus.pending.rawValue == "pending")
        #expect(SyncStatus.syncing.rawValue == "syncing")
        #expect(SyncStatus.synced.rawValue == "synced")
        #expect(SyncStatus.failed.rawValue == "failed")
        #expect(SyncStatus.queued.rawValue == "queued")
    }

    @Test("WhisperModelSize all cases")
    func whisperModelSizeAllCases() {
        let cases = WhisperModelSize.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.tiny))
        #expect(cases.contains(.base))
        #expect(cases.contains(.small))
        #expect(cases.contains(.medium))
        #expect(cases.contains(.large))
    }

    @Test("WhisperModelSize display properties")
    func whisperModelDisplayProperties() {
        #expect(WhisperModelSize.medium.displayName == "Medium")
        #expect(WhisperModelSize.tiny.diskSize == "~75 MB")
        #expect(WhisperModelSize.large.diskSize == "~2.9 GB")
        #expect(!WhisperModelSize.medium.estimatedSpeed.isEmpty)
    }

    @Test("MeetingRecord JSON encoding of arrays")
    func jsonArrayEncoding() throws {
        var record = MeetingRecord(title: "Test Meeting")
        record.actionItems = ["Item 1", "Item 2"]
        record.keyDecisions = ["Decision A"]

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(MeetingRecord.self, from: data)

        #expect(decoded.actionItems == ["Item 1", "Item 2"])
        #expect(decoded.keyDecisions == ["Decision A"])
    }

    @Test("MeetingRecord JSON encoding with nil arrays")
    func jsonNilArrayEncoding() throws {
        let record = MeetingRecord(title: "No Items")

        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        let decoded = try JSONDecoder().decode(MeetingRecord.self, from: data)

        #expect(decoded.actionItems == nil)
        #expect(decoded.keyDecisions == nil)
    }
}
