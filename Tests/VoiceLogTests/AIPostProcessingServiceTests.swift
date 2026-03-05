import Testing
import Foundation
@testable import VoiceLog

@Suite("AIPostProcessingService Tests")
struct AIPostProcessingServiceTests {

    @Test("ProcessingResult initialization")
    func processingResultInit() {
        let result = ProcessingResult(
            summary: "Meeting discussed project timeline",
            actionItems: ["Review PR", "Update docs"],
            keyDecisions: ["Use Swift for backend"],
            suggestedTitle: "Project Timeline Discussion"
        )

        #expect(result.summary == "Meeting discussed project timeline")
        #expect(result.actionItems.count == 2)
        #expect(result.keyDecisions.count == 1)
        #expect(result.suggestedTitle == "Project Timeline Discussion")
    }

    @Test("ProcessingResult Codable conformance")
    func processingResultCodable() throws {
        let result = ProcessingResult(
            summary: "A summary",
            actionItems: ["Action 1"],
            keyDecisions: ["Decision 1"],
            suggestedTitle: "Test Title"
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ProcessingResult.self, from: data)

        #expect(decoded.summary == result.summary)
        #expect(decoded.actionItems == result.actionItems)
        #expect(decoded.keyDecisions == result.keyDecisions)
        #expect(decoded.suggestedTitle == result.suggestedTitle)
    }

    @Test("ProcessingResult Equatable conformance")
    func processingResultEquatable() {
        let r1 = ProcessingResult(
            summary: "Same",
            actionItems: ["A"],
            keyDecisions: ["D"],
            suggestedTitle: "Title"
        )
        let r2 = ProcessingResult(
            summary: "Same",
            actionItems: ["A"],
            keyDecisions: ["D"],
            suggestedTitle: "Title"
        )
        let r3 = ProcessingResult(
            summary: "Different",
            actionItems: ["A"],
            keyDecisions: ["D"],
            suggestedTitle: "Title"
        )

        #expect(r1 == r2)
        #expect(r1 != r3)
    }

    @Test("ProcessingResult empty arrays")
    func processingResultEmptyArrays() {
        let result = ProcessingResult(
            summary: "Short meeting",
            actionItems: [],
            keyDecisions: [],
            suggestedTitle: "Quick Sync"
        )

        #expect(result.actionItems.isEmpty)
        #expect(result.keyDecisions.isEmpty)
    }
}
