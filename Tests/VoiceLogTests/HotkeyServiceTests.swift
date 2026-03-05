import Testing
import Foundation
import Carbon.HIToolbox
@testable import VoiceLog

@Suite("HotkeyService Tests")
struct HotkeyServiceTests {

    @MainActor
    @Test("Default key combo is Control+Option+R")
    func defaultKeyCombo() {
        let combo = HotkeyService.defaultKeyCombo
        #expect(combo.keyCode == UInt32(kVK_ANSI_R))
        #expect(combo.modifiers == UInt32(controlKey | optionKey))
    }

    @MainActor
    @Test("Conflict detection for known system shortcuts")
    func conflictDetection() {
        // Cmd+Q (Quit) should conflict
        let conflictsQuit = HotkeyService.checkConflict(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey)
        )
        #expect(conflictsQuit == true)

        // Cmd+W (Close window) should conflict
        let conflictsClose = HotkeyService.checkConflict(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(cmdKey)
        )
        #expect(conflictsClose == true)

        // Control+Option+R (our default) should NOT conflict
        let noConflict = HotkeyService.checkConflict(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey)
        )
        #expect(noConflict == false)
    }

    @MainActor
    @Test("Display string for default combo")
    func displayString() {
        let display = HotkeyService.displayString(
            keyCode: UInt32(kVK_ANSI_R),
            modifiers: UInt32(controlKey | optionKey)
        )
        #expect(display.contains("R"))
        #expect(!display.isEmpty)
    }

    @MainActor
    @Test("Initial state is not registered")
    func initialState() {
        let service = HotkeyService()
        #expect(service.isRegistered == false)
    }
}
