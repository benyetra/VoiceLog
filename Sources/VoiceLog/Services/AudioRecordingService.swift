import AVFoundation
import Combine
import CoreAudio
import Foundation

// MARK: - AudioRecordingError

enum AudioRecordingError: LocalizedError {
    case engineStartFailed(underlying: Error)
    case noInputNode
    case fileCreationFailed(underlying: Error)
    case notRecording
    case deviceNotFound(String)
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputNode:
            return "No audio input node available."
        case .fileCreationFailed(let error):
            return "Failed to create audio file: \(error.localizedDescription)"
        case .notRecording:
            return "No recording is in progress."
        case .deviceNotFound(let id):
            return "Audio device not found: \(id)"
        case .permissionDenied:
            return "Microphone access was denied."
        }
    }
}

// MARK: - AudioInputDevice

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

// MARK: - AudioRecordingService

@MainActor
final class AudioRecordingService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var currentDuration: TimeInterval = 0
    /// Current audio input level in dB (-160 = silence, 0 = maximum).
    @Published private(set) var currentAudioLevel: Float = -160

    // MARK: - Private Properties

    private var audioRecorder: AVAudioRecorder?
    private var currentFileURL: URL?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0

    // MARK: - Storage Directory

    /// Returns the recordings directory, respecting the user's configured local storage path.
    private static var storageDirectory: URL {
        let basePath = AppSettings.shared.localStoragePath
        let dir = URL(fileURLWithPath: basePath, isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Device Enumeration

    /// Lists available audio input devices using CoreAudio.
    static func listInputDevices() -> [AudioInputDevice] {
        var devices: [AudioInputDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard status == noErr else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return devices }

        for deviceID in deviceIDs {
            // Check if this device has input streams
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(
                deviceID,
                &inputAddress,
                0,
                nil,
                &inputSize
            )

            let streamCount = Int(inputSize) / MemoryLayout<AudioStreamID>.size
            guard status == noErr, streamCount > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>>.size)
            var unmanagedName: Unmanaged<CFString>?
            status = AudioObjectGetPropertyData(
                deviceID,
                &nameAddress,
                0,
                nil,
                &nameSize,
                &unmanagedName
            )

            if status == noErr, let cfName = unmanagedName?.takeUnretainedValue() {
                devices.append(AudioInputDevice(
                    id: String(deviceID),
                    name: cfName as String
                ))
            }
        }

        return devices
    }

    // MARK: - Recording Control

    /// Checks microphone permission and requests it if needed.
    /// - Returns: true if microphone access is granted.
    static func requestMicrophonePermission() async -> Bool {
        if #available(macOS 14.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Checks if microphone permission is currently granted.
    static var hasMicrophonePermission: Bool {
        if #available(macOS 14.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        } else {
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    /// Starts recording audio from the specified device (or default input).
    /// - Parameter deviceID: The CoreAudio device ID string. Pass nil for the default input device.
    /// - Returns: The URL of the file being recorded to.
    @discardableResult
    func startRecording(deviceID: String? = nil) throws -> URL {
        guard !isRecording else {
            return currentFileURL!
        }

        // Check microphone permission
        guard Self.hasMicrophonePermission else {
            throw AudioRecordingError.permissionDenied
        }

        // If a specific device is requested, set it on the audio engine's input node
        // so AVAudioRecorder picks it up as the active device.
        if let deviceID = deviceID, let audioDeviceID = AudioDeviceID(deviceID) {
            setInputDevice(audioDeviceID)
        }

        let fileName = "recording_\(ISO8601DateFormatter().string(from: Date())).wav"
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = Self.storageDirectory.appendingPathComponent(fileName)

        // Record 16 kHz mono 16-bit PCM — optimal for Whisper, no conversion needed
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        } catch {
            throw AudioRecordingError.fileCreationFailed(underlying: error)
        }

        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioRecordingError.engineStartFailed(
                underlying: NSError(
                    domain: "VoiceLog",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder.record() returned false"]
                )
            )
        }

        self.audioRecorder = recorder
        self.currentFileURL = fileURL
        self.isRecording = true
        self.isPaused = false
        self.accumulatedDuration = 0
        self.recordingStartTime = Date()

        startDurationTimer()

        return fileURL
    }

    /// Stops the current recording and returns the file URL and final duration.
    @discardableResult
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }

        stopDurationTimer()

        audioRecorder?.stop()
        audioRecorder = nil

        isRecording = false
        isPaused = false

        let url = currentFileURL
        let finalDuration = currentDuration

        currentFileURL = nil
        recordingStartTime = nil
        accumulatedDuration = 0
        currentDuration = 0

        guard let url = url else { return nil }
        return (url: url, duration: finalDuration)
    }

    /// Pauses the current recording. Audio data is not captured while paused.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }

        audioRecorder?.pause()
        isPaused = true

        // Accumulate duration up to this pause
        if let startTime = recordingStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        recordingStartTime = nil
        stopDurationTimer()
    }

    /// Resumes a paused recording.
    func resumeRecording() {
        guard isRecording, isPaused else { return }

        audioRecorder?.record()
        isPaused = false
        recordingStartTime = Date()
        startDurationTimer()
    }

    // MARK: - Device Selection

    /// Sets the input device for recording using CoreAudio.
    /// AVAudioRecorder on macOS records from the system default input device.
    /// This sets the requested device as the default input device.
    private func setInputDevice(_ deviceID: AudioDeviceID) {
        var deviceIDValue = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDValue
        )
        if status != noErr {
            print("[AudioRecordingService] Warning: could not set input device \(deviceID), using system default")
        }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func updateDuration() {
        guard isRecording, !isPaused, let startTime = recordingStartTime else { return }
        currentDuration = accumulatedDuration + Date().timeIntervalSince(startTime)

        // Update audio level metering
        audioRecorder?.updateMeters()
        currentAudioLevel = audioRecorder?.averagePower(forChannel: 0) ?? -160
    }

    deinit {
        // Ensure cleanup if service is deallocated while recording
        MainActor.assumeIsolated {
            if isRecording {
                _ = stopRecording()
            }
        }
    }
}
