import Carbon.HIToolbox
import Cocoa

// MARK: - File-Private Shared State for Carbon Callback

/// Mutable storage accessible to both `HotkeyService` and the global Carbon event handler
/// function in this file. Using file-private scope because `InstallEventHandler` requires
/// a plain C function pointer, which cannot capture context.
private var _activeHotkeyHandler: (() -> Void)?

// MARK: - HotkeyService

@MainActor
final class HotkeyService: ObservableObject {

    // MARK: - Default Key Combo

    /// Default hotkey: Control + Option + R
    nonisolated static let defaultKeyCombo: (keyCode: UInt32, modifiers: UInt32) = (
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey)
    )

    /// Unique hotkey signature identifier ("VLog").
    private static let hotkeySignature: FourCharCode = {
        let chars: [UInt8] = [
            UInt8(ascii: "V"),
            UInt8(ascii: "L"),
            UInt8(ascii: "o"),
            UInt8(ascii: "g"),
        ]
        return FourCharCode(chars[0]) << 24
            | FourCharCode(chars[1]) << 16
            | FourCharCode(chars[2]) << 8
            | FourCharCode(chars[3])
    }()

    private static let hotkeyID: UInt32 = 1

    // MARK: - Properties

    @Published var isRegistered: Bool = false

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Init / Deinit

    init() {}

    deinit {
        unregisterSync()
    }

    // MARK: - Register

    /// Registers a global hotkey with the given key code and modifier combination.
    ///
    /// - Parameters:
    ///   - keyCombo: A tuple of Carbon virtual key code and modifier flags.
    ///   - handler: Closure invoked on the main thread when the hotkey is pressed.
    func register(
        keyCombo: (keyCode: UInt32, modifiers: UInt32) = HotkeyService.defaultKeyCombo,
        handler: @escaping () -> Void
    ) {
        // Unregister any existing hotkey first
        unregister()

        // Store the handler in file-private storage so the C callback can reach it
        _activeHotkeyHandler = handler

        // Install the Carbon event handler for hotkey events
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            _activeHotkeyHandler = nil
            return
        }

        // Register the hotkey itself
        let hotkeyIDSpec = EventHotKeyID(
            signature: Self.hotkeySignature,
            id: Self.hotkeyID
        )

        let registerStatus = RegisterEventHotKey(
            keyCombo.keyCode,
            keyCombo.modifiers,
            hotkeyIDSpec,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerStatus == noErr {
            isRegistered = true
        } else {
            // Clean up the event handler if hotkey registration failed
            if let ref = eventHandlerRef {
                RemoveEventHandler(ref)
            }
            eventHandlerRef = nil
            _activeHotkeyHandler = nil
            isRegistered = false
        }
    }

    // MARK: - Unregister

    /// Unregisters the current global hotkey and removes the event handler.
    func unregister() {
        unregisterSync()
    }

    private nonisolated func unregisterSync() {
        MainActor.assumeIsolated {
            if let ref = hotkeyRef {
                UnregisterEventHotKey(ref)
                hotkeyRef = nil
            }

            if let ref = eventHandlerRef {
                RemoveEventHandler(ref)
                eventHandlerRef = nil
            }

            _activeHotkeyHandler = nil
            isRegistered = false
        }
    }

    // MARK: - Conflict Check

    /// Checks whether the given key combination might conflict with common system shortcuts.
    /// This is a best-effort heuristic check, not an exhaustive system query.
    ///
    /// - Parameters:
    ///   - keyCode: Carbon virtual key code.
    ///   - modifiers: Carbon modifier flags.
    /// - Returns: `true` if a potential conflict is detected.
    static func checkConflict(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let systemShortcuts: [(UInt32, UInt32)] = [
            // Command+Q - Quit
            (UInt32(kVK_ANSI_Q), UInt32(cmdKey)),
            // Command+W - Close window
            (UInt32(kVK_ANSI_W), UInt32(cmdKey)),
            // Command+H - Hide
            (UInt32(kVK_ANSI_H), UInt32(cmdKey)),
            // Command+Tab - App switcher
            (UInt32(kVK_Tab), UInt32(cmdKey)),
            // Command+Space - Spotlight
            (UInt32(kVK_Space), UInt32(cmdKey)),
            // Control+Space - Input source toggle
            (UInt32(kVK_Space), UInt32(controlKey)),
            // Command+Control+F - Fullscreen
            (UInt32(kVK_ANSI_F), UInt32(cmdKey | controlKey)),
            // Command+Option+Esc - Force Quit
            (UInt32(kVK_Escape), UInt32(cmdKey | optionKey)),
            // Control+Command+Q - Lock screen
            (UInt32(kVK_ANSI_Q), UInt32(controlKey | cmdKey)),
            // Shift+Command+3 - Screenshot full
            (UInt32(kVK_ANSI_3), UInt32(shiftKey | cmdKey)),
            // Shift+Command+4 - Screenshot selection
            (UInt32(kVK_ANSI_4), UInt32(shiftKey | cmdKey)),
            // Shift+Command+5 - Screenshot options
            (UInt32(kVK_ANSI_5), UInt32(shiftKey | cmdKey)),
        ]

        for (sysKey, sysMods) in systemShortcuts {
            if keyCode == sysKey && modifiers == sysMods {
                return true
            }
        }

        return false
    }

    // MARK: - Display Helpers

    /// Returns a human-readable string for a key combo (e.g., "⌃⌥R").
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 { parts.append("\u{2303}") }  // Control
        if modifiers & UInt32(optionKey) != 0 { parts.append("\u{2325}") }   // Option
        if modifiers & UInt32(shiftKey) != 0 { parts.append("\u{21E7}") }    // Shift
        if modifiers & UInt32(cmdKey) != 0 { parts.append("\u{2318}") }      // Command

        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)

        return parts.joined()
    }

    /// Maps a Carbon virtual key code to a display string.
    private static func keyCodeToString(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Return: return "\u{21A9}"      // Return
        case kVK_Tab: return "\u{21E5}"          // Tab
        case kVK_Space: return "\u{2423}"        // Space
        case kVK_Delete: return "\u{232B}"       // Delete
        case kVK_Escape: return "\u{238B}"       // Escape
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "?"
        }
    }
}

// MARK: - Carbon Event Handler (Global C Function)

/// Global C-compatible function pointer for the Carbon event handler.
/// `InstallEventHandler` requires a plain C function pointer -- closures and
/// instance methods are not allowed. This function reads from file-private
/// `_activeHotkeyHandler` to dispatch the event.
private func carbonHotkeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotkeyID
    )

    guard status == noErr else { return status }

    // Dispatch back to the main thread to invoke the handler
    DispatchQueue.main.async {
        _activeHotkeyHandler?()
    }

    return noErr
}
