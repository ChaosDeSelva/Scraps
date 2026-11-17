import Foundation
import AVFoundation
import SQLite3
import Speech

struct FeatureFailure: Error { let message: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw FeatureFailure(message: message) }
}

@main struct FeatureTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scraps-features-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var item = Scrap(title: "Planning", content: "Release on Friday. Ask Mina to review.", kind: .note, tags: ["private-tag"], source: "private-source")
        item.annotations = [Annotation(text: "Follow up on Thursday.")]
        let without = try AIRequest.context(item, includeNotes: false)
        try require(!without.contains("Thursday") && !without.contains("private-tag") && !without.contains("private-source"), "Context must exclude unchecked notes, tags and sources")
        let withNotes = try AIRequest.context(item, includeNotes: true)
        try require(withNotes.contains("Thursday") && withNotes.contains("Friday"), "Selected content and included notes must be sent")
        let messages = [AIMessage(role: "user", text: "Summarize"), AIMessage(role: "assistant", text: "Release Friday."), AIMessage(role: "user", text: "Who reviews?")]
        let request = try AIRequest.body(provider: .openAIKey, model: "test-model", context: withNotes, messages: messages)
        let body = try JSONSerialization.jsonObject(with: request) as! [String: Any]
        try require(body["store"] as? Bool == false, "OpenAI response storage must be disabled")
        try require((body["input"] as? [[String: Any]])?.count == 4, "Chat must preserve prior questions and answers")
        try require(body["tools"] == nil, "BYOK requests must offer no tools")
        let openRequest = try AIService.makeRequest(provider: .openAIKey, model: "test-model", context: without, messages: messages, key: "test-only-key")
        let claudeRequest = try AIService.makeRequest(provider: .anthropicKey, model: "test-model", context: without, messages: messages, key: "test-only-key")
        try require(openRequest.url?.host == "api.openai.com" && openRequest.httpMethod == "POST", "OpenAI requests must target its fixed HTTPS endpoint")
        try require(openRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key", "OpenAI authentication must use the header")
        try require(claudeRequest.url?.host == "api.anthropic.com" && claudeRequest.value(forHTTPHeaderField: "x-api-key") == "test-only-key", "Anthropic must use its own endpoint and key header")
        try require(!String(decoding: openRequest.httpBody!, as: UTF8.self).contains("test-only-key"), "Keys must never enter the model context")
        let openAI = Data(#"{"output":[{"content":[{"type":"output_text","text":"Mina."}]}]}"#.utf8)
        let anthropic = Data(#"{"content":[{"type":"thinking","text":"hidden"},{"type":"text","text":"Mina."}]}"#.utf8)
        let first = try AIRequest.response(openAI, provider: .openAIKey)
        let second = try AIRequest.response(anthropic, provider: .anthropicKey)
        try require(first == "Mina." && second == "Mina.", "Parse only provider answer text")
        item.content = String(repeating: "x", count: 240_001)
        do { _ = try AIRequest.context(item, includeNotes: false); throw FeatureFailure(message: "Oversized item accepted") }
        catch is AIError {}
        let codex = AccountCLI.arguments(.codex, model: "", directory: directory)
        try require(codex.contains("--ignore-user-config") && codex.contains("--ephemeral") && codex.contains("project_doc_max_bytes=0"), "Codex must isolate settings, history and project instructions")
        try require(codex.contains("log_dir=\"" + directory.path + "\""), "CLI log paths must use valid TOML, not escaped JSON slashes")
        try require(codex.contains("computer_use") && codex.contains("memories.use_memories=false"), "Unrelated computer access and memory context must be disabled")
        let claude = AccountCLI.arguments(.claude, model: "")
        try require(claude.contains("--safe-mode") && claude.contains("--no-session-persistence") && claude.contains("--strict-mcp-config"), "Claude must isolate customizations, MCP and history")
        print("PASS selected-item context boundaries, conversation payloads, response parsing and request limits")

        let preferences = UserDefaults(suiteName: "scraps-test-" + UUID().uuidString)!
        let settings = AISettings(defaults: preferences)
        settings.changeProvider(.openAIKey); settings.model = "test-openai"
        settings.changeProvider(.anthropicKey); settings.model = "test-anthropic"
        settings.changeProvider(.openAIKey)
        try require(settings.model == "test-openai", "Each provider must retain its own model")
        let restored = AISettings(defaults: preferences)
        try require(restored.provider == .openAIKey && restored.model == "test-openai", "Provider and model must survive reopening")
        let (exit, echoed) = try await CLIProcess().run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [], input: "Quoted café \"text\"\n", directory: directory)
        try require(exit == 0 && String(decoding: echoed, as: UTF8.self) == "Quoted café \"text\"\n", "CLI prompt must survive stdin exactly")
        let cancelTask = Task { try await CLIProcess().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], input: "", directory: directory) }
        try await Task.sleep(for: .milliseconds(100)); cancelTask.cancel()
        do { _ = try await cancelTask.value; throw FeatureFailure(message: "Cancelled process succeeded") }
        catch is AIError {} catch is CancellationError {}
        print("PASS connection preferences, subprocess stdin and cancellation")

        let store = ScrapStore(url: directory.appendingPathComponent("library.sqlite"))
        let recordingID = UUID()
        let folder = store.recordingsDirectory.appendingPathComponent(recordingID.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try tone(url: folder.appendingPathComponent("microphone.caf"), seconds: 1, frequency: 440)
        try tone(url: folder.appendingPathComponent("system.caf"), seconds: 1, frequency: 880)
        try JSONEncoder().encode(["microphone": 10.0, "system": 10.5]).write(to: folder.appendingPathComponent("timing.json"))
        let writerDirectory = directory.appendingPathComponent("writer")
        try FileManager.default.createDirectory(at: writerDirectory, withIntermediateDirectories: true)
        let writer = AudioTrackWriter(directory: writerDirectory)
        writer.append(try sample(time: 10), name: "microphone")
        writer.append(try sample(time: 10.2), name: "microphone")
        writer.close()
        try require(writer.failure == nil, "Stream samples must write successfully")
        let written = try AVAudioFile(forReading: writerDirectory.appendingPathComponent("microphone.caf"))
        try require(abs(Double(written.length) / written.processingFormat.sampleRate - 0.3) < 0.001, "Writer must insert silence for a missing 0.1-second buffer")
        let duration = try await AudioFinalizer.finish(directory: folder)
        try require(abs(duration - 1.5) < 0.03, "Mix must preserve the 0.5-second source offset")
        let playable = try AVAudioFile(forReading: folder.appendingPathComponent("audio.m4a"))
        try require(abs(Double(playable.length) / playable.processingFormat.sampleRate - 1.5) < 0.1, "Final audio must be playable at the expected duration")
        let permissions = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("audio.m4a").path)[.posixPermissions] as? NSNumber
        try require(permissions?.intValue == 0o600, "Audio must be owner-readable only")
        let attachment = RecordingAttachment(id: recordingID, duration: duration, source: .both)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        guard let id = store.saveRecording(attachment, title: "Synthetic recording", tags: "test, audio", startedAt: started) else { throw FeatureFailure(message: "Recording save failed") }
        let reopened = ScrapStore(url: store.databaseURL)
        try require(reopened.item(id)?.recording == attachment && reopened.item(id)?.createdAt == started, "Audio metadata and capture date must round-trip")
        var edit = CaptureDraft(item: reopened.item(id)!)
        edit.title = "Renamed before transcription"
        try require(reopened.update(id, draft: edit), "An untranscribed recording must be editable")
        try require(reopened.saveTranscript("Mina will review on Friday.", to: id), "Transcript must save")
        try require(reopened.saveTranscript("Alternate wording.", to: id), "Repeated transcription must save")
        try require(reopened.item(id)?.content == "Mina will review on Friday." && reopened.item(id)?.annotations.last?.text.contains("Alternate wording") == true, "Retranscription must preserve edited text")
        reopened.filter = .recordings; reopened.query = "Mina"
        try require(reopened.visibleItems.count == 1, "Transcripts must be searchable in Recordings")
        reopened.trash(id); reopened.restore(id)
        try require(FileManager.default.fileExists(atPath: reopened.audioURL(attachment).path), "Trash and restore must retain the audio")
        var db: OpaquePointer?
        sqlite3_open(store.databaseURL.path, &db)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        sqlite3_step(statement)
        try require(sqlite3_column_int(statement, 0) == 2, "Recording libraries must reject older app versions")
        sqlite3_finalize(statement)
        sqlite3_exec(db, "CREATE TRIGGER fail_recording BEFORE INSERT ON scraps BEGIN SELECT RAISE(ABORT, 'test failure'); END", nil, nil, nil)
        try require(store.saveRecording(attachment, title: "Must fail", tags: "", startedAt: started) == nil, "Failed database writes must not report saved")
        try require(FileManager.default.fileExists(atPath: store.audioURL(attachment).path), "Failed save must keep the audio for recovery")
        sqlite3_close(db)
        print("PASS source synchronization, playable mix, private permissions, metadata persistence, transcript search and write failure recovery")

        let recoveryStore = ScrapStore(url: directory.appendingPathComponent("recovery/library.sqlite"))
        let recovery = RecordingManifest(id: UUID(), source: .both, startedAt: started, title: "Recovered sample", tags: "recovered")
        let recoveryFolder = recoveryStore.recordingsDirectory.appendingPathComponent(recovery.id.uuidString)
        try FileManager.default.createDirectory(at: recoveryFolder, withIntermediateDirectories: true)
        try tone(url: recoveryFolder.appendingPathComponent("microphone.caf"), seconds: 0.2, frequency: 440)
        try JSONEncoder().encode(recovery).write(to: recoveryFolder.appendingPathComponent("manifest.json"))
        let recorder = RecordingController(store: recoveryStore)
        try require(recorder.recoverable.count == 1, "Unfinished source files must be discoverable")
        await recorder.recover(recovery)
        try require(recoveryStore.items.first?.recording?.source == .microphone, "Partial recovery must identify the source actually captured")
        try require(recorder.recoverable.isEmpty && !recorder.hasWork, "Successful recovery must stop appearing as unfinished")
        try require(recorder.message?.contains("other source produced no samples") == true, "Partial capture must surface a warning")
        print("PASS interrupted recording discovery and partial-source recovery")

        if CommandLine.arguments.contains("--keychain-check") {
            let vault = APIKeyStore(service: "local.scraps.test." + UUID().uuidString)
            defer { try? vault.remove(.openAIKey) }
            try vault.save("test-only-key", for: .openAIKey)
            let value = try vault.read(.openAIKey)
            try require(value == "test-only-key", "Keychain must round-trip the test key")
            try vault.save("replacement-test-key", for: .openAIKey)
            let updated = try vault.read(.openAIKey)
            try require(updated == "replacement-test-key", "Updating a key must replace the previous value")
            try vault.remove(.openAIKey)
            do { _ = try vault.read(.openAIKey); throw FeatureFailure(message: "Deleted key remained readable") }
            catch is AIError {}
            print("PASS Keychain save, replace and remove using an isolated temporary service")
        }
        if CommandLine.arguments.contains("--live-cli") {
            for provider in [AIProvider.codex, .claude] {
                do {
                    let response = try await AIService.reply(provider: provider, model: "", context: "{\"content\":\"The meeting is Friday. Mina will review the draft.\"}", messages: [AIMessage(role: "user", text: "Summarize in one sentence. Do not use tools.")])
                    print("LIVE \(provider.command): \(response.prefix(350))")
                } catch { print("LIVE \(provider.command): \(error.localizedDescription)") }
            }
        }
        if CommandLine.arguments.contains("--speech-check") {
            if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
                let installed = await SpeechTranscriber.installedLocales
                print("Installed on-device speech locales: " + installed.map(\.identifier).joined(separator: ", "))
                if let english = installed.first(where: { $0.identifier == "en_US" }) ?? installed.first(where: { $0.identifier.hasPrefix("en") }),
                   await AssetInventory.status(forModules: [SpeechTranscriber(locale: english, preset: .transcription)]) == .installed {
                    let voice = directory.appendingPathComponent("spoken.caf")
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
                    process.arguments = ["-o", voice.path, "The meeting is Friday. Mina will review the draft."]
                    try process.run(); process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        let result = try await LocalTranscription.transcribe(url: voice, locale: english, downloadModel: false) { print($0) }
                        try require(result.lowercased().contains("friday"), "Synthetic speech should transcribe its key fact")
                        print("PASS on-device synthetic speech transcription: " + result)
                    }
                } else { print("SKIP speech inference: required English assets are not installed; no download was started") }
            } else { print("SKIP speech inference: SpeechTranscriber is unavailable on this Mac") }
        }
        print("All feature checks passed.")
    }
    static func sample(time: Double) throws -> CMSampleBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
        pcm.frameLength = 4800
        for index in 0..<4800 { pcm.floatChannelData![0][index] = 0.1 }
        var description: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        try require(formatStatus == noErr, "Could not create synthetic audio format")
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var buffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: 4800,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &buffer)
        try require(status == noErr, "Could not create synthetic sample buffer")
        let result = buffer!
        let dataStatus = CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList)
        try require(dataStatus == noErr, "Could not copy synthetic samples")
        CMSampleBufferSetDataReady(result)
        return result
    }
    static func tone(url: URL, seconds: Double, frequency: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let count = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        buffer.frameLength = count
        for index in 0..<Int(count) { buffer.floatChannelData![0][index] = Float(sin(Double(index) * frequency * 2 * .pi / format.sampleRate) * 0.2) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
