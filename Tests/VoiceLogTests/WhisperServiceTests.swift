import Testing
import Foundation
@testable import VoiceLog

@Suite("WhisperService Tests")
struct WhisperServiceTests {

    @Test("WhisperError descriptions")
    func whisperErrorDescriptions() {
        let errors: [WhisperError] = [
            .whisperNotInstalled,
            .modelNotFound(.medium),
            .transcriptionFailed("bad audio"),
            .timeout,
            .audioFileMissing(URL(fileURLWithPath: "/tmp/test.wav")),
            .ffmpegNotInstalled,
            .chunkingFailed("split error"),
            .downloadFailed("network error"),
        ]

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    @Test("WhisperService initializes with default state")
    func defaultState() {
        let service = WhisperService()
        #expect(service.transcriptionProgress == 0.0)
    }
}
