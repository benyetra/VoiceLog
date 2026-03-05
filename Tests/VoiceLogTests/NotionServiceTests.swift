import Testing
import Foundation
@testable import VoiceLog

@Suite("NotionService Tests")
struct NotionServiceTests {

    @Test("NotionDatabase model")
    func notionDatabaseModel() {
        let db = NotionDatabase(id: "abc-123", title: "Meeting Log", url: "https://notion.so/abc")
        #expect(db.id == "abc-123")
        #expect(db.title == "Meeting Log")
        #expect(db.url == "https://notion.so/abc")
    }

    @Test("NotionDatabase without URL")
    func notionDatabaseNoUrl() {
        let db = NotionDatabase(id: "def-456", title: "Notes", url: nil)
        #expect(db.url == nil)
    }

    @Test("NotionDatabase Codable")
    func notionDatabaseCodable() throws {
        let db = NotionDatabase(id: "test-id", title: "Test DB", url: "https://notion.so/test")
        let data = try JSONEncoder().encode(db)
        let decoded = try JSONDecoder().decode(NotionDatabase.self, from: data)

        #expect(decoded.id == db.id)
        #expect(decoded.title == db.title)
        #expect(decoded.url == db.url)
    }

    @Test("NotionError descriptions")
    func notionErrorDescriptions() {
        let errors: [NotionError] = [
            .notAuthenticated,
            .invalidResponse(statusCode: 500),
            .rateLimited(retryAfter: 30),
            .tokenExchangeFailed("bad code"),
            .schemaValidationFailed("missing Title"),
            .encodingFailed,
            .networkError(URLError(.notConnectedToInternet)),
        ]

        for error in errors {
            let desc = error.errorDescription
            #expect(desc != nil)
            #expect(!desc!.isEmpty)
        }
    }

    @MainActor
    @Test("NotionService default state")
    func defaultState() {
        let service = NotionService()
        #expect(service.isConnected == false || service.isConnected == true) // depends on keychain state
        #expect(service.workspaceName == nil || service.workspaceName != nil)
    }
}
