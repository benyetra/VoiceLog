import AVFoundation
import Combine
import CoreMedia
import ScreenCaptureKit

// MARK: - SystemAudioError

enum SystemAudioError: LocalizedError {
    case noDisplayAvailable
    case permissionDenied
    case captureAlreadyRunning
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display available for audio capture."
        case .permissionDenied:
            return "Screen recording permission is required to capture system audio. Grant permission in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .captureAlreadyRunning:
            return "System audio capture is already running."
        case .captureFailed(let reason):
            return "System audio capture failed: \(reason)"
        }
    }
}

// MARK: - SystemAudioCaptureService

@MainActor
final class SystemAudioCaptureService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var isCapturing = false

    // MARK: - Private Properties

    private var stream: SCStream?
    private var audioWriter: SystemAudioFileWriter?
    private var captureOutputURL: URL?
    private let audioQueue = DispatchQueue(label: "com.voicelog.systemaudio", qos: .userInitiated)

    // MARK: - Permission

    /// Requests screen capture permission by attempting to enumerate shareable content.
    /// On first call, macOS will show the permission dialog.
    static func requestPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Capture Control

    /// Starts capturing system audio to the specified file URL.
    /// The output file is 16 kHz mono 16-bit PCM WAV — matching Whisper's preferred format.
    func startCapture(to outputURL: URL) async throws {
        guard !isCapturing else { throw SystemAudioError.captureAlreadyRunning }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw SystemAudioError.permissionDenied
        }

        guard let display = content.displays.first else {
            throw SystemAudioError.noDisplayAvailable
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16_000
        config.channelCount = 1

        // Minimize video overhead — we only want audio.
        // SCStream requires a display filter, so we capture a tiny video frame at minimum rate.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        let writer = SystemAudioFileWriter(outputURL: outputURL)
        try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: audioQueue)

        self.stream = stream
        self.audioWriter = writer
        self.captureOutputURL = outputURL

        do {
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.audioWriter = nil
            self.captureOutputURL = nil
            throw SystemAudioError.captureFailed(error.localizedDescription)
        }

        isCapturing = true
    }

    /// Stops capturing system audio and returns the output file URL.
    @discardableResult
    func stopCapture() async -> URL? {
        guard isCapturing, let stream = stream else { return nil }

        do {
            try await stream.stopCapture()
        } catch {
            print("[SystemAudio] Error stopping capture: \(error)")
        }

        audioWriter?.close()

        let url = captureOutputURL
        self.stream = nil
        self.audioWriter = nil
        self.captureOutputURL = nil
        isCapturing = false

        // Verify the file has content
        if let url = url {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if fileSize < 100 {
                print("[SystemAudio] Warning: system audio file is very small (\(fileSize) bytes), may be empty")
                return nil
            }
        }

        return url
    }
}

// MARK: - SCStreamDelegate

extension SystemAudioCaptureService: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[SystemAudio] Stream stopped with error: \(error)")
        Task { @MainActor in
            self.isCapturing = false
        }
    }
}

// MARK: - SystemAudioFileWriter

/// Handles writing audio sample buffers from ScreenCaptureKit to a WAV file.
/// This class is accessed exclusively from the audioQueue.
private final class SystemAudioFileWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    private let outputURL: URL
    private var audioFile: AVAudioFile?
    private var hasInitialized = false

    init(outputURL: URL) {
        self.outputURL = outputURL
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        guard let formatDescription = sampleBuffer.formatDescription,
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        var asbd = asbdPtr.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM else { return }
        guard let inputFormat = AVAudioFormat(streamDescription: &asbd) else { return }

        // Initialize the output audio file on the first valid buffer
        if !hasInitialized {
            hasInitialized = true
            do {
                // Write as 16-bit PCM WAV, accepting Float32 buffers from ScreenCaptureKit.
                // AVAudioFile handles the float→int16 conversion internally.
                audioFile = try AVAudioFile(
                    forWriting: outputURL,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: asbd.mSampleRate,
                        AVNumberOfChannelsKey: asbd.mChannelsPerFrame,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                    ],
                    commonFormat: .pcmFormatFloat32,
                    interleaved: inputFormat.isInterleaved
                )
            } catch {
                print("[SystemAudio] Failed to create output file: \(error)")
                return
            }
        }

        guard audioFile != nil else { return }

        // Convert CMSampleBuffer → AVAudioPCMBuffer
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }

        // Copy raw audio data into the PCM buffer's channel data
        if let channelData = pcmBuffer.floatChannelData {
            let bytesToCopy = min(totalLength, Int(frameCount) * MemoryLayout<Float>.size * Int(asbd.mChannelsPerFrame))
            memcpy(channelData[0], dataPointer, bytesToCopy)
        }

        do {
            try audioFile?.write(from: pcmBuffer)
        } catch {
            print("[SystemAudio] Write error: \(error)")
        }
    }

    func close() {
        audioFile = nil
    }
}
