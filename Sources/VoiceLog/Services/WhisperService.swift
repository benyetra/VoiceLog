import Foundation
import Combine

// MARK: - WhisperError

enum WhisperError: LocalizedError {
    case whisperNotInstalled
    case modelNotFound(WhisperModelSize)
    case transcriptionFailed(String)
    case timeout
    case audioFileMissing(URL)
    case ffmpegNotInstalled
    case chunkingFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .whisperNotInstalled:
            return "Whisper CLI is not installed. Install via `pip install openai-whisper` or build whisper.cpp."
        case .modelNotFound(let model):
            return "Whisper model '\(model.rawValue)' not found. Download it first."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .timeout:
            return "Transcription timed out."
        case .audioFileMissing(let url):
            return "Audio file not found at: \(url.path)"
        case .ffmpegNotInstalled:
            return "ffmpeg is not installed. Whisper requires ffmpeg to process audio. Install via: brew install ffmpeg"
        case .chunkingFailed(let reason):
            return "Failed to split audio into chunks: \(reason)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        }
    }
}

// MARK: - WhisperService

final class WhisperService: ObservableObject {

    // MARK: - Published State

    @Published var transcriptionProgress: Double = 0.0

    // MARK: - Configuration

    /// Path to the whisper CLI executable. Can be overridden by user settings.
    var whisperExecutablePath: String = "/usr/local/bin/whisper"

    /// Path to ffmpeg for audio chunking.
    var ffmpegExecutablePath: String = "/usr/local/bin/ffmpeg"

    /// Maximum segment duration in seconds before chunking is applied.
    private let maxSegmentDuration: TimeInterval = 600 // 10 minutes

    /// Timeout per chunk in seconds.
    private let timeoutPerChunk: TimeInterval = 1800 // 30 minutes

    /// Cached user shell environment (lazy-loaded once)
    private lazy var userShellEnvironment: [String: String] = {
        loadUserShellEnvironment()
    }()

    // MARK: - Whisper Installation Check

    /// Checks if the whisper CLI is available at the configured path or in common locations.
    func isWhisperInstalled() -> Bool {
        // Check explicitly configured path first
        if FileManager.default.isExecutableFile(atPath: whisperExecutablePath) {
            return true
        }

        // Check common install locations including pyenv, Homebrew, and pip paths
        let candidatePaths = commonExecutablePaths(for: "whisper")
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                whisperExecutablePath = path
                return true
            }
        }

        // Last resort: resolve via the user's login shell to pick up pyenv, PATH, etc.
        if let resolvedPath = resolveViaShell("whisper") {
            whisperExecutablePath = resolvedPath
            return true
        }

        return false
    }

    /// Checks if ffmpeg is available.
    func isFFmpegInstalled() -> Bool {
        if FileManager.default.isExecutableFile(atPath: ffmpegExecutablePath) {
            return true
        }
        let candidates = commonExecutablePaths(for: "ffmpeg")
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                ffmpegExecutablePath = path
                return true
            }
        }
        if let resolved = resolveViaShell("ffmpeg") {
            ffmpegExecutablePath = resolved
            return true
        }
        return false
    }

    /// Returns common paths where a CLI tool might be installed (Homebrew, pyenv, pip, etc.)
    private func commonExecutablePaths(for name: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.pyenv/shims/\(name)",
            "\(home)/.local/bin/\(name)",
        ]

        // Check all pyenv Python version bin dirs
        let pyenvVersionsDir = "\(home)/.pyenv/versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: pyenvVersionsDir) {
            for version in versions {
                paths.append("\(pyenvVersionsDir)/\(version)/bin/\(name)")
            }
        }

        return paths
    }

    /// Resolves an executable by running `which` inside the user's login shell.
    /// This picks up PATH modifications from .zshrc/.bashrc (pyenv, nvm, etc.)
    private func resolveViaShell(_ name: String) -> String? {
        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        // -l = login shell (loads profile), -c = run command
        process.arguments = ["-l", "-c", "which \(name)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty, path != name {
                    return path
                }
            }
        } catch {}

        return nil
    }

    /// Loads environment variables from the user's login shell so subprocess
    /// invocations pick up pyenv, Homebrew, and other PATH additions.
    private func loadUserShellEnvironment() -> [String: String] {
        let process = Process()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "env"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessInfo.processInfo.environment
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return ProcessInfo.processInfo.environment
        }

        var env: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<equalsIndex])
            let value = String(line[line.index(after: equalsIndex)...])
            env[key] = value
        }

        return env.isEmpty ? ProcessInfo.processInfo.environment : env
    }

    /// Configures a Process to run with the user's full shell environment.
    private func configureProcess(_ process: Process) {
        process.environment = userShellEnvironment
    }

    // MARK: - Model Management

    /// Downloads a Whisper model using the whisper CLI's built-in download mechanism.
    /// - Parameter model: The model size to download.
    func downloadModel(_ model: WhisperModelSize) async throws {
        guard isWhisperInstalled() else {
            throw WhisperError.whisperNotInstalled
        }

        // Running `whisper --model <size>` on a dummy file triggers model download
        // if the model isn't already cached. We use a minimal approach here.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperExecutablePath)

        // Use the whisper CLI with --model flag; passing a nonexistent file
        // will cause it to error after downloading the model.
        // A better approach: use Python to download directly.
        let script = """
        import whisper
        whisper.load_model("\(model.rawValue)")
        print("MODEL_DOWNLOADED")
        """

        let pythonPath = resolveViaShell("python3") ?? "/usr/bin/python3"
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", script]
        configureProcess(process)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw WhisperError.downloadFailed(error.localizedDescription)
        }

        // Wait asynchronously
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.downloadFailed(errorMessage)
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file using the Whisper CLI.
    /// - Parameters:
    ///   - audioURL: Path to the audio file (WAV, MP3, etc.).
    ///   - model: The Whisper model size to use.
    ///   - language: Optional language code (e.g., "en"). Nil for auto-detection.
    /// - Returns: The full transcription text.
    func transcribe(
        audioURL: URL,
        model: WhisperModelSize,
        language: String? = nil
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WhisperError.audioFileMissing(audioURL)
        }

        guard isWhisperInstalled() else {
            throw WhisperError.whisperNotInstalled
        }

        // Whisper requires ffmpeg to decode audio files
        guard isFFmpegInstalled() else {
            throw WhisperError.ffmpegNotInstalled
        }

        await MainActor.run { self.transcriptionProgress = 0.0 }

        // Get audio duration to determine if chunking is needed
        let duration = try await getAudioDuration(url: audioURL)

        let transcript: String
        if duration > maxSegmentDuration {
            transcript = try await transcribeWithChunking(
                audioURL: audioURL,
                model: model,
                language: language,
                totalDuration: duration
            )
        } else {
            transcript = try await transcribeSingleFile(
                audioURL: audioURL,
                model: model,
                language: language,
                estimatedDuration: duration
            )
            await MainActor.run { self.transcriptionProgress = 1.0 }
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Single File Transcription

    private func transcribeSingleFile(
        audioURL: URL,
        model: WhisperModelSize,
        language: String?,
        estimatedDuration: TimeInterval = 60
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisperExecutablePath)
        configureProcess(process)

        var arguments = [
            audioURL.path,
            "--model", model.rawValue,
            "--output_format", "txt",
            "--output_dir", NSTemporaryDirectory(),
        ]

        if let language = language {
            arguments.append(contentsOf: ["--language", language])
        }

        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Real-time stderr monitoring for progress updates.
        // Whisper outputs timestamp lines like "[00:00.000 --> 00:30.000]  text"
        // to stderr. We parse the end timestamp to estimate progress.
        let stderrAccumulator = StderrAccumulator()
        let audioDuration = max(estimatedDuration, 1.0)

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrAccumulator.append(data)

            if let text = String(data: data, encoding: .utf8) {
                // Parse end timestamps: --> MM:SS.mmm
                let pattern = #"-->\s*(\d{2}):(\d{2})\.\d{3}"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                   let minutesRange = Range(match.range(at: 1), in: text),
                   let secondsRange = Range(match.range(at: 2), in: text) {
                    let minutes = Double(text[minutesRange]) ?? 0
                    let seconds = Double(text[secondsRange]) ?? 0
                    let endTime = minutes * 60 + seconds
                    let progress = min(endTime / audioDuration, 0.95)
                    Task { @MainActor [weak self] in
                        if let self = self {
                            self.transcriptionProgress = max(self.transcriptionProgress, progress)
                        }
                    }
                }
            }
        }

        // Signal that transcription has started
        await MainActor.run { self.transcriptionProgress = 0.02 }

        do {
            try process.run()
        } catch {
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw WhisperError.transcriptionFailed(error.localizedDescription)
        }

        // Wait with timeout
        let didComplete = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    continuation.resume(returning: false)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutPerChunk, execute: timeoutWorkItem)

            process.terminationHandler = { _ in
                timeoutWorkItem.cancel()
                continuation.resume(returning: true)
            }
        }

        // Stop reading stderr
        errorPipe.fileHandleForReading.readabilityHandler = nil

        guard didComplete else {
            throw WhisperError.timeout
        }

        let errorText = stderrAccumulator.text

        guard process.terminationStatus == 0 else {
            throw WhisperError.transcriptionFailed(errorText.isEmpty ? "Unknown error" : errorText)
        }

        // Whisper outputs a .txt file alongside/in the output directory
        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let txtURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(baseName + ".txt")

        var transcript = ""
        if FileManager.default.fileExists(atPath: txtURL.path) {
            transcript = try String(contentsOf: txtURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: txtURL)
        } else {
            // Fallback: read stdout
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            transcript = String(data: outputData, encoding: .utf8) ?? ""
        }

        // Detect whisper errors that end up in the output (e.g. missing ffmpeg)
        let errorPatterns = ["FileNotFoundError", "No such file or directory", "Skipping", "Error", "ModuleNotFoundError"]
        if transcript.isEmpty || errorPatterns.contains(where: { transcript.contains($0) }) {
            let detail = transcript.isEmpty ? errorText : transcript
            if detail.contains("ffmpeg") || detail.contains("ff") {
                throw WhisperError.ffmpegNotInstalled
            }
            throw WhisperError.transcriptionFailed(detail.isEmpty ? "No transcript produced" : detail)
        }

        return transcript
    }

    // MARK: - Chunked Transcription

    private func transcribeWithChunking(
        audioURL: URL,
        model: WhisperModelSize,
        language: String?,
        totalDuration: TimeInterval
    ) async throws -> String {
        guard isFFmpegInstalled() else {
            throw WhisperError.ffmpegNotInstalled
        }

        let chunkURLs = try await splitAudioIntoChunks(audioURL: audioURL, totalDuration: totalDuration)
        defer {
            // Clean up chunk files
            for url in chunkURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        var fullTranscript = ""
        let totalChunks = Double(chunkURLs.count)

        for (index, chunkURL) in chunkURLs.enumerated() {
            let chunkText = try await transcribeSingleFile(
                audioURL: chunkURL,
                model: model,
                language: language
            )

            if !fullTranscript.isEmpty && !chunkText.isEmpty {
                fullTranscript += " "
            }
            fullTranscript += chunkText

            let progress = Double(index + 1) / totalChunks
            await MainActor.run { self.transcriptionProgress = progress }
        }

        return fullTranscript
    }

    /// Splits an audio file into chunks of maxSegmentDuration using ffmpeg.
    private func splitAudioIntoChunks(audioURL: URL, totalDuration: TimeInterval) async throws -> [URL] {
        let chunkDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("voicelog_chunks_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: chunkDir, withIntermediateDirectories: true)

        let chunkPattern = chunkDir.appendingPathComponent("chunk_%03d.wav").path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegExecutablePath)
        configureProcess(process)
        process.arguments = [
            "-i", audioURL.path,
            "-f", "segment",
            "-segment_time", String(Int(maxSegmentDuration)),
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_f32le",
            chunkPattern,
        ]

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw WhisperError.chunkingFailed(error.localizedDescription)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.chunkingFailed(errorMessage)
        }

        // Enumerate chunk files in order
        let contents = try FileManager.default.contentsOfDirectory(
            at: chunkDir,
            includingPropertiesForKeys: nil
        )
        let chunkURLs = contents
            .filter { $0.pathExtension == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !chunkURLs.isEmpty else {
            throw WhisperError.chunkingFailed("No chunk files were produced.")
        }

        return chunkURLs
    }

    // MARK: - Stderr Accumulator

    /// Thread-safe accumulator for stderr data from subprocess output.
    private class StderrAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ newData: Data) {
            lock.lock()
            data.append(newData)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    // MARK: - Audio Duration

    // MARK: - Audio Mixing

    /// Mixes microphone and system audio files into a single file using ffmpeg.
    /// Both inputs are mixed down to 16 kHz mono 16-bit PCM WAV for Whisper.
    func mixAudioFiles(micURL: URL, systemAudioURL: URL, outputURL: URL) async throws {
        guard isFFmpegInstalled() else {
            throw WhisperError.ffmpegNotInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegExecutablePath)
        configureProcess(process)
        process.arguments = [
            "-y",
            "-i", micURL.path,
            "-i", systemAudioURL.path,
            "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest:normalize=0",
            "-ar", "16000",
            "-ac", "1",
            "-acodec", "pcm_s16le",
            outputURL.path,
        ]

        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw WhisperError.transcriptionFailed("Failed to start ffmpeg for audio mixing: \(error.localizedDescription)")
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw WhisperError.transcriptionFailed("Audio mixing failed: \(errorMessage)")
        }
    }

    // MARK: - Audio Duration

    /// Gets the duration of an audio file using ffprobe (part of ffmpeg).
    private func getAudioDuration(url: URL) async throws -> TimeInterval {
        let ffprobePath: String
        if let resolved = resolveViaShell("ffprobe") {
            ffprobePath = resolved
        } else {
            // Estimate based on file size for WAV: 16kHz * 1ch * 4 bytes = 64KB/s
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attrs?[.size] as? Double ?? 0
            return fileSize / (16_000 * 2) // approximate for 16kHz 16-bit mono WAV
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        configureProcess(process)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            url.path,
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            // Fallback: file size estimation
            return 600 // assume 10 minutes to trigger single-file path
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let duration = TimeInterval(text) {
            return duration
        }

        // Fallback
        return 600
    }
}
