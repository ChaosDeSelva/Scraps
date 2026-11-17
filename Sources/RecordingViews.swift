import SwiftUI
import AVFoundation
import Speech

struct RecordingView: View {
    @ObservedObject var recorder: RecordingController
    let openLibrary: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Record something worth keeping.").font(.system(size: 23, weight: .bold))
                    Text("Audio stays on this Mac.").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "waveform").font(.system(size: 28)).foregroundStyle(Palette.muted)
            }
            Picker("Audio source", selection: $recorder.source) {
                ForEach(RecordingSource.allCases) { Text($0.title).tag($0).disabled($0 != .microphone && !RecordingController.supportsSystemAudio) }
            }.disabled(recorder.hasWork)
            TextField("Title (optional)", text: $recorder.title).textFieldStyle(.roundedBorder).disabled(recorder.hasWork)
            TextField("Tags, separated by commas", text: $recorder.tags).textFieldStyle(.roundedBorder).disabled(recorder.hasWork)
            HStack(spacing: 12) {
                Circle().fill(recorder.recording ? Color.red : Palette.muted).frame(width: 10, height: 10)
                if recorder.recording, let start = recorder.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("Recording · " + durationLabel(Date().timeIntervalSince(start))).font(.system(size: 20, weight: .medium, design: .monospaced))
                    }
                } else { Text(recorder.working ? recorder.activity : "Ready when you are").font(.system(size: 18, weight: .medium)) }
                Spacer()
                if recorder.working { ProgressView().controlSize(.small) }
            }.padding(20).background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 8))
            Text("macOS will ask for microphone and system audio access when needed. For calls, headphones help prevent echo. Record only when the people involved expect it.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            if let message = recorder.message { Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            if !recorder.recoverable.isEmpty && !recorder.hasWork {
                Menu("Recover unfinished recording…") {
                    ForEach(recorder.recoverable, id: \.id) { value in
                        Button(value.title.isEmpty ? value.startedAt.formatted() : value.title) { Task { await recorder.recover(value) } }
                    }
                }.font(.system(size: 12))
            }
            Spacer(minLength: 0)
            HStack {
                Button("Open library", action: openLibrary).buttonStyle(PaperButton())
                Spacer()
                if recorder.recording {
                    Button("Stop and save") { Task { await recorder.stop() } }.buttonStyle(PaperButton(primary: true)).disabled(recorder.working)
                } else {
                    Button("Start recording") { Task { await recorder.start() } }.buttonStyle(PaperButton(primary: true)).disabled(recorder.working)
                }
            }
        }.padding(28).frame(width: 570, height: 550).background(Palette.canvas).foregroundStyle(Palette.ink)
            .onAppear { recorder.refreshRecovery() }
    }
}

func durationLabel(_ duration: TimeInterval) -> String {
    let seconds = max(0, Int(duration.isFinite ? duration : 0))
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                          : String(format: "%d:%02d", seconds / 60, seconds % 60)
}

@MainActor final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var error: String?
    private var player: AVAudioPlayer?
    func toggle(url: URL) {
        do {
            if player == nil {
                let value = try AVAudioPlayer(contentsOf: url)
                value.delegate = self
                player = value; duration = value.duration
            }
            guard let player else { return }
            if playing { player.pause(); playing = false }
            else { playing = player.play(); if !playing { error = "Couldn’t play this recording." } }
        } catch { self.error = "The recording couldn’t be opened. Check that its audio file is still in the local data folder." }
    }
    func tick() { if let player { position = player.currentTime } }
    func seek(_ seconds: Double) { player?.currentTime = seconds; position = seconds }
    func stop() { player?.stop(); playing = false }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false; self.position = 0; self.player?.currentTime = 0 }
    }
}

struct RecordingAttachmentView: View {
    @ObservedObject var store: ScrapStore
    let item: Scrap
    let attachment: RecordingAttachment
    @StateObject private var playback = AudioPlayback()
    @State private var transcription: Task<Void, Never>?
    @State private var busy = false
    @State private var status: String?
    @State private var transcript: String?
    @State private var languages: [Locale] = [Locale.current]
    @State private var language = Locale.current.identifier
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Recording", systemImage: "waveform").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(attachment.source.title).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            HStack(spacing: 12) {
                Button { playback.toggle(url: store.audioURL(attachment)) } label: {
                    Image(systemName: playback.playing ? "pause.fill" : "play.fill").frame(width: 18)
                }.buttonStyle(PaperButton()).accessibilityLabel(playback.playing ? "Pause recording" : "Play recording")
                Slider(value: Binding(get: { playback.position }, set: { playback.seek($0) }), in: 0...max(1, playback.duration))
                    .disabled(playback.duration == 0).accessibilityLabel("Playback position")
                Text(durationLabel(playback.position) + " / " + durationLabel(attachment.duration)).font(.system(size: 11, design: .monospaced)).fixedSize()
            }
            if item.trashedAt == nil {
                if LocalTranscription.available {
                    Picker("Language", selection: $language) {
                        ForEach(languages, id: \.identifier) { locale in
                            Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                        }
                    }.font(.system(size: 12)).disabled(busy)
                    HStack {
                        if busy {
                            ProgressView().controlSize(.small)
                            Button("Cancel transcription") { transcription?.cancel() }.buttonStyle(PaperButton(compact: true))
                        } else {
                            Button(item.content.isEmpty ? "Create transcript" : "Transcribe again") { transcribe() }.buttonStyle(PaperButton(compact: true))
                        }
                        Spacer()
                    }
                    Text("Runs on this Mac. Apple may download a speech model first. Existing text is preserved when transcribing again.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("On-device transcription needs macOS 26 or later and supported Apple hardware. You can still play and annotate this recording.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let status = status ?? playback.error { Text(status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            if let transcript {
                ScrollView { Text(transcript).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 150)
                HStack {
                    Button("Retry saving transcript") { save(transcript) }.buttonStyle(PaperButton(compact: true))
                    Button("Copy transcript") { copyToClipboard(transcript) }.buttonStyle(PaperButton(compact: true))
                }
            }
        }.padding(16).background(Palette.canvas).clipShape(RoundedRectangle(cornerRadius: 7))
            .onReceive(timer) { _ in playback.tick() }
            .onDisappear { playback.stop(); transcription?.cancel() }
            .task {
                if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
                    let supported = await SpeechTranscriber.supportedLocales
                    languages = supported.sorted { $0.identifier < $1.identifier }
                    if let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) { language = match.identifier }
                    else if let first = languages.first { language = first.identifier }
                }
            }
    }
    private func transcribe() {
        busy = true; status = "Preparing on-device transcription…"
        let locale = Locale(identifier: language), url = store.audioURL(attachment)
        transcription = Task {
            do {
                let text = try await LocalTranscription.transcribe(url: url, locale: locale) { status = $0 }
                try Task.checkCancellation()
                save(text)
            } catch { status = Task.isCancelled ? "Transcription cancelled. Your audio is saved." : error.localizedDescription }
            busy = false
        }
    }
    private func save(_ text: String) {
        if store.saveTranscript(text, to: item.id) { transcript = nil; status = "Transcript saved. You can edit, search, or ask AI about it." }
        else { transcript = text; status = store.errorMessage ?? "Couldn’t save the transcript. You can retry or copy it below." }
    }
}
