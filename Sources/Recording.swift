import AVFoundation
import ScreenCaptureKit
import Speech
import Combine

struct RecordingError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct RecordingManifest: Codable {
    var id: UUID
    var source: RecordingSource
    var startedAt: Date
    var title: String
    var tags: String
}

final class AudioTrackWriter {
    private let directory: URL
    private var files: [String: AVAudioFile] = [:]
    private var starts: [String: Double] = [:]
    private(set) var failure: Error?
    init(directory: URL) { self.directory = directory }

    func append(_ buffer: CMSampleBuffer, name: String) {
        guard failure == nil, buffer.isValid, buffer.numSamples > 0 else { return }
        do {
            try buffer.withAudioBufferList { list, _ in
                guard var description = buffer.formatDescription?.audioStreamBasicDescription else { return }
                guard let format = AVAudioFormat(streamDescription: &description),
                      let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else {
                    throw RecordingError("The audio device returned an unsupported format.")
                }
                let time = buffer.presentationTimeStamp.seconds
                guard time.isFinite else { return }
                if files[name] == nil {
                    files[name] = try AVAudioFile(forWriting: directory.appendingPathComponent(name + ".caf"), settings: format.settings,
                                                  commonFormat: format.commonFormat, interleaved: format.isInterleaved)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent(name + ".caf").path)
                    starts[name] = time
                    try JSONEncoder().encode(starts).write(to: directory.appendingPathComponent("timing.json"), options: [.atomic])
                }
                guard let file = files[name], let start = starts[name] else { return }
                let target = AVAudioFramePosition(((time - start) * format.sampleRate).rounded())
                let gap = target - file.length
                // Preserve pauses and dropped buffers so microphone and Mac audio stay in sync.
                if gap > 0 {
                    guard gap < AVAudioFramePosition(format.sampleRate * 3600) else { throw RecordingError("The audio device clock changed. Stop and save this recording.") }
                    var remaining = gap
                    while remaining > 0 {
                        let count = AVAudioFrameCount(min(remaining, 8192))
                        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { throw RecordingError("Couldn’t allocate an audio buffer.") }
                        silence.frameLength = count
                        for audio in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
                            if let bytes = audio.mData { memset(bytes, 0, Int(audio.mDataByteSize)) }
                        }
                        try file.write(from: silence)
                        remaining -= AVAudioFramePosition(count)
                    }
                }
                try file.write(from: pcm)
            }
        } catch { failure = error }
    }
    func close() { files.removeAll() }
}

final class StreamAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "scraps.audio.write", qos: .userInitiated)
    let writer: AudioTrackWriter
    var stopped: ((Error) -> Void)?
    init(directory: URL) { writer = AudioTrackWriter(directory: directory) }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let name: String
        if type == .audio { name = "system" }
        else if #available(macOS 15.0, *), type == .microphone { name = "microphone" }
        else { return }
        writer.append(sampleBuffer, name: name)
        if let error = writer.failure { stopped?(error) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopped?(error) }
    func close() { queue.sync { writer.close() } }
}

enum AudioFinalizer {
    static func finish(directory: URL) async throws -> TimeInterval {
        let output = directory.appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: output.path) {
            return try await AVURLAsset(url: output).load(.duration).seconds
        }
        let timingURL = directory.appendingPathComponent("timing.json")
        let starts = (try? JSONDecoder().decode([String: Double].self, from: Data(contentsOf: timingURL))) ?? [:]
        let names = ["microphone", "system"].filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0 + ".caf").path) }
        guard !names.isEmpty else { throw RecordingError("No audio was captured. Check the input device and recording permissions, then try again.") }
        let composition = AVMutableComposition()
        let mix = AVMutableAudioMix()
        var inputs: [AVMutableAudioMixInputParameters] = []
        let first = names.compactMap { starts[$0] }.min() ?? 0
        for name in names {
            let asset = AVURLAsset(url: directory.appendingPathComponent(name + ".caf"))
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }
            let offset = max(0, (starts[name] ?? first) - first)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: CMTime(seconds: offset, preferredTimescale: 48_000))
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(names.count > 1 ? 0.5 : 1, at: .zero)
            inputs.append(input)
        }
        guard composition.duration.seconds > 0 else { throw RecordingError("The audio files contain no playable samples.") }
        mix.inputParameters = inputs
        let temporary = directory.appendingPathComponent("mix.m4a")
        try? FileManager.default.removeItem(at: temporary)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw RecordingError("Couldn’t prepare the audio file. The original tracks are still saved.")
        }
        exporter.audioMix = mix
        if #available(macOS 15.0, *) {
            try await exporter.export(to: temporary, as: .m4a)
        } else {
            exporter.outputURL = temporary
            exporter.outputFileType = .m4a
            await exporter.export()
            guard exporter.status == .completed else {
                throw exporter.error ?? RecordingError("Couldn’t finish the audio file. The original tracks are still saved; try Recover recording.")
            }
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: output)
        return composition.duration.seconds
    }
}

private final class MicrophoneObserver: NSObject, AVAudioRecorderDelegate {
    var interrupted: (() -> Void)?
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { interrupted?() }
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { interrupted?() }
}

@MainActor final class RecordingController: ObservableObject {
    @Published var source: RecordingSource = .both
    @Published var title = ""
    @Published var tags = ""
    @Published private(set) var recording = false
    @Published private(set) var working = false
    @Published private(set) var activity = "Preparing…"
    @Published private(set) var startedAt: Date?
    @Published var message: String?
    @Published private(set) var recoverable: [RecordingManifest] = []
    private var stream: SCStream?
    private var output: StreamAudioOutput?
    private var microphone: AVAudioRecorder?
    private var microphoneObserver: MicrophoneObserver?
    private var manifest: RecordingManifest?
    private var store: ScrapStore
    var hasWork: Bool { recording || working }

    static var supportsSystemAudio: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
    init(store: ScrapStore) {
        self.store = store
        if !Self.supportsSystemAudio { source = .microphone }
        refreshRecovery()
    }
    private func interrupted(_ id: UUID) async {
        guard recording, !working, manifest?.id == id else { return }
        await stop()
        message = "Capture was interrupted. Any available audio was kept. Check permissions and your audio devices before recording again."
    }
    func refreshRecovery() {
        let known = Set(store.items.compactMap { $0.recording?.id })
        let directories = (try? FileManager.default.contentsOfDirectory(at: store.recordingsDirectory, includingPropertiesForKeys: nil)) ?? []
        recoverable = directories.compactMap { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent), !known.contains(id),
                  let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                  let value = try? JSONDecoder().decode(RecordingManifest.self, from: data), value.id == id else { return nil }
            return value
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private func directory(_ manifest: RecordingManifest) -> URL { store.recordingsDirectory.appendingPathComponent(manifest.id.uuidString) }
    func start() async {
        guard !hasWork else { return }
        working = true; activity = "Preparing…"; message = nil; manifest = nil
        defer { working = false }
        do {
            if source != .system {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw RecordingError("Allow Scraps in System Settings → Privacy & Security → Microphone, then try again.") }
            }
            if source != .microphone {
                guard #available(macOS 15.0, *) else { throw RecordingError("Mac audio recording requires macOS 15 or later. Microphone recording is available on this Mac.") }
            }
            let shareable = source == .microphone ? nil : try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let value = RecordingManifest(id: UUID(), source: source, startedAt: Date(), title: title, tags: tags)
            let folder = directory(value)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(value).write(to: folder.appendingPathComponent("manifest.json"), options: [.atomic])
            manifest = value
            if source == .microphone {
                let recorder = try AVAudioRecorder(url: folder.appendingPathComponent("microphone.caf"), settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
                let observer = MicrophoneObserver()
                observer.interrupted = { [weak self] in Task { @MainActor in await self?.interrupted(value.id) } }
                recorder.delegate = observer
                microphoneObserver = observer
                guard recorder.record() else { throw RecordingError("The microphone couldn’t start recording. Check your input device.") }
                microphone = recorder
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recorder.url.path)
            } else if #available(macOS 15.0, *) {
                guard let display = shareable?.displays.first else { throw RecordingError("No display is available for Mac audio capture.") }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.captureMicrophone = source == .both
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
                let sink = StreamAudioOutput(directory: folder)
                sink.stopped = { [weak self] _ in
                    Task { @MainActor in await self?.interrupted(value.id) }
                }
                let capture = SCStream(filter: filter, configuration: config, delegate: sink)
                try capture.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
                if source == .both { try capture.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue) }
                // No screen output is registered; only audio samples are retained.
                output = sink; stream = capture
                try await capture.startCapture()
            }
            startedAt = value.startedAt; recording = true
        } catch {
            microphone?.stop(); microphone = nil; microphoneObserver = nil
            if let stream { try? await stream.stopCapture() }
            output?.close(); stream = nil; output = nil
            if let manifest {
                let folder = directory(manifest)
                let hasSamples = ["microphone.caf", "system.caf"].contains {
                    ((try? AVAudioFile(forReading: folder.appendingPathComponent($0)))?.length ?? 0) > 0
                }
                if !hasSamples { try? FileManager.default.removeItem(at: folder) }
            }
            message = "Couldn’t start recording. \(error.localizedDescription)"
            refreshRecovery()
        }
    }
    func stop() async {
        guard recording, !working, let manifest else { return }
        working = true; activity = "Saving…"
        microphone?.stop(); microphone = nil; microphoneObserver = nil
        if let stream { try? await stream.stopCapture() }
        output?.close(); stream = nil; output = nil
        recording = false
        await save(manifest)
        working = false
    }
    func recover(_ value: RecordingManifest) async {
        guard !hasWork else { return }
        working = true; activity = "Recovering…"; message = nil
        await save(value)
        working = false
    }
    private func save(_ value: RecordingManifest) async {
        do {
            let folder = directory(value)
            let duration = try await AudioFinalizer.finish(directory: folder)
            var actualSource = value.source
            if value.source == .both {
                let mic = FileManager.default.fileExists(atPath: folder.appendingPathComponent("microphone.caf").path)
                let system = FileManager.default.fileExists(atPath: folder.appendingPathComponent("system.caf").path)
                if mic && !system { actualSource = .microphone }
                if system && !mic { actualSource = .system }
            }
            let attachment = RecordingAttachment(id: value.id, duration: duration, source: actualSource)
            guard store.saveRecording(attachment, title: value.title, tags: value.tags, startedAt: value.startedAt) != nil else {
                throw RecordingError(store.errorMessage ?? "Couldn’t save to the library. The audio is kept for recovery.")
            }
            for name in ["microphone.caf", "system.caf", "timing.json", "manifest.json"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
            message = actualSource == value.source
                ? "Recording saved. Open the library to play it or create a transcript."
                : "Saved \(actualSource.title) only; the other source produced no samples. Check its input or permission before recording again."
            title = ""; tags = ""; manifest = nil; startedAt = nil
        } catch { message = error.localizedDescription + " Your recorded files remain in the local data folder." }
        refreshRecovery()
    }
}

enum LocalTranscription {
    static var available: Bool {
        if #available(macOS 26.0, *) { return SpeechTranscriber.isAvailable }
        return false
    }
    static func transcribe(url: URL, locale: Locale, downloadModel: Bool = true, progress: @escaping @MainActor (String) -> Void) async throws -> String {
        guard #available(macOS 26.0, *), SpeechTranscriber.isAvailable else {
            throw RecordingError("On-device transcription requires macOS 26 or later and supported Apple hardware.")
        }
        guard let language = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw RecordingError("Apple’s on-device transcription does not support this language on this Mac.") }
        let transcriber = SpeechTranscriber(locale: language, preset: .transcription)
        if await AssetInventory.status(forModules: [transcriber]) != .installed {
            guard downloadModel else { throw RecordingError("The speech model needs installation before this check can run.") }
            if let assets = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                await progress("Downloading Apple’s speech model…")
                try await assets.downloadAndInstall()
            }
        }
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let reader = Task { () throws -> String in
            var pieces: [String] = []
            for try await result in transcriber.results { pieces.append(String(result.text.characters)) }
            return pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        await progress("Transcribing on this Mac…")
        do {
            let file = try AVAudioFile(forReading: url)
            try await withTaskCancellationHandler(operation: {
                if let end = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: end) }
                else { try await analyzer.finalizeAndFinishThroughEndOfInput() }
            }, onCancel: { Task { await analyzer.cancelAndFinishNow() } })
            let text = try await reader.value
            try Task.checkCancellation()
            guard !text.isEmpty else { throw RecordingError("No speech was detected. The recording is still available to play.") }
            return text
        } catch {
            reader.cancel(); await analyzer.cancelAndFinishNow(); throw error
        }
    }
}
