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

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?
    private var accumulatedDuration: TimeInterval = 0

    /// Target sample rate for Whisper-optimized recording.
    private let targetSampleRate: Double = 16_000
    private let targetChannels: AVAudioChannelCount = 1

    // MARK: - Storage Directory

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport
            .appendingPathComponent("VoiceLog", isDirectory: true)
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

    /// Starts recording audio from the specified device (or default input) to a 16kHz mono WAV file.
    /// - Parameter deviceID: The CoreAudio device ID string. Pass nil for the default input device.
    /// - Returns: The URL of the file being recorded to.
    @discardableResult
    func startRecording(deviceID: String? = nil) throws -> URL {
        guard !isRecording else {
            return currentFileURL!
        }

        let engine = AVAudioEngine()

        // Set specific input device if requested
        if let deviceID = deviceID, let audioDeviceID = AudioDeviceID(deviceID) {
            let inputNode = engine.inputNode
            let audioUnit = inputNode.audioUnit!
            var deviceIDValue = audioDeviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceIDValue,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                throw AudioRecordingError.deviceNotFound(deviceID)
            }
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0 else {
            throw AudioRecordingError.noInputNode
        }

        // Create output WAV file in 16kHz mono format (optimal for Whisper)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        )!

        let fileName = "recording_\(ISO8601DateFormatter().string(from: Date())).wav"
            .replacingOccurrences(of: ":", with: "-")
        let fileURL = Self.storageDirectory.appendingPathComponent(fileName)

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw AudioRecordingError.fileCreationFailed(underlying: error)
        }

        // Install a tap on the input node to capture audio
        // Use a converter if the input format differs from our target format
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self, weak audioFile] buffer, _ in
            guard let audioFile = audioFile else { return }

            if let converter = converter {
                // Convert to 16kHz mono
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate
                )
                guard frameCapacity > 0,
                      let convertedBuffer = AVAudioPCMBuffer(
                          pcmFormat: outputFormat,
                          frameCapacity: frameCapacity
                      )
                else { return }

                var error: NSError?
                var allConsumed = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if allConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    allConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }

                if error == nil, convertedBuffer.frameLength > 0 {
                    do {
                        try audioFile.write(from: convertedBuffer)
                    } catch {
                        Task { @MainActor [weak self] in
                            self?.handleRecordingError(error)
                        }
                    }
                }
            } else {
                // Formats match, write directly
                do {
                    try audioFile.write(from: buffer)
                } catch {
                    Task { @MainActor [weak self] in
                        self?.handleRecordingError(error)
                    }
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecordingError.engineStartFailed(underlying: error)
        }

        self.audioEngine = engine
        self.audioFile = audioFile
        self.currentFileURL = fileURL
        self.isRecording = true
        self.isPaused = false
        self.accumulatedDuration = 0
        self.recordingStartTime = Date()

        startDurationTimer()

        return fileURL
    }

    /// Stops the current recording and returns the file URL of the completed recording.
    @discardableResult
    func stopRecording() -> URL? {
        guard isRecording else { return nil }

        stopDurationTimer()

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Close the audio file by releasing the reference
        audioFile = nil

        isRecording = false
        isPaused = false

        let url = currentFileURL
        currentFileURL = nil
        recordingStartTime = nil
        accumulatedDuration = 0
        currentDuration = 0

        return url
    }

    /// Pauses the current recording. Audio data is not captured while paused.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }

        audioEngine?.pause()
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

        do {
            try audioEngine?.start()
            isPaused = false
            recordingStartTime = Date()
            startDurationTimer()
        } catch {
            handleRecordingError(error)
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
    }

    // MARK: - Error Handling

    private func handleRecordingError(_ error: Error) {
        // Save partial audio by stopping gracefully
        print("[AudioRecordingService] Recording error: \(error.localizedDescription)")
        _ = stopRecording()
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
