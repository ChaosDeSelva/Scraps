import SwiftUI

struct AISettingsView: View {
    @ObservedObject var settings: AISettings = .shared
    @State private var key = ""
    @State private var status: String?
    @State private var working = false
    @State private var connection: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI connections").font(.system(size: 20, weight: .bold))
            Text("Use a signed-in CLI account or your own API key. Nothing is sent until you press Send in an item’s AI chat.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            Picker("Provider", selection: Binding(get: { settings.provider }, set: {
                connection?.cancel(); working = false; key = ""; status = nil; settings.changeProvider($0)
            })) {
                ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
            }
            if settings.provider.isCLI {
                Text("Uses the official \(settings.provider.command) installation on this Mac. Sign in there with your subscription or its other supported account options. Scraps does not read or copy login tokens.")
                    .font(.system(size: 12)).foregroundStyle(Palette.body).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Sign in…") { connect(login: true) }.buttonStyle(PaperButton())
                    Button("Check connection") { connect(login: false) }.buttonStyle(PaperButton())
                    if working { ProgressView().controlSize(.small) }
                }.disabled(working)
                Link("Installation and account setup ↗", destination: URL(string: settings.provider == .codex
                     ? "https://developers.openai.com/codex/cli" : "https://code.claude.com/docs/en/quickstart")!)
                    .font(.system(size: 12))
            } else {
                SecureField("New API key", text: $key).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("API key")
                HStack {
                    Button("Save key in Keychain") {
                        do { try APIKeyStore.shared.save(key, for: settings.provider); key = ""; status = "Key saved in this Mac’s Keychain." }
                        catch { status = error.localizedDescription }
                    }.buttonStyle(PaperButton()).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove key") {
                        do { try APIKeyStore.shared.remove(settings.provider); key = ""; status = "Key removed." }
                        catch { status = error.localizedDescription }
                    }.buttonStyle(PaperButton())
                }
                Text("API usage is billed by your provider. Keys are kept in Keychain and are never stored with your notes.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Text("Model").font(.system(size: 12, weight: .semibold))
            TextField(settings.provider.isCLI ? "Model (blank uses CLI default)" : "Model", text: $settings.model)
                .textFieldStyle(.roundedBorder)
            if let status { Text(status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
            Spacer(minLength: 0)
        }.padding(24).onDisappear { connection?.cancel(); key = "" }
    }

    private func connect(login: Bool) {
        let provider = settings.provider
        working = true
        status = login ? "Complete sign-in in the browser opened by the CLI…" : "Checking…"
        connection = Task {
            do {
                let result = try await AccountCLI.connect(provider, login: login)
                guard !Task.isCancelled else { return }
                status = result
            } catch { if !Task.isCancelled { status = error.localizedDescription } }
            if !Task.isCancelled { working = false }
        }
    }
}

struct AIChatView: View {
    @ObservedObject var store: ScrapStore
    let item: Scrap
    let initialPrompt: String
    @ObservedObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var includeNotes = true
    @State private var messages: [AIMessage] = []
    @State private var request: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?
    @State private var saved = Set<UUID>()
    @State private var showSettings = false
    @State private var showContext = false
    @State private var sessionProvider: AIProvider?
    @State private var sessionModel = ""

    private var activeProvider: AIProvider { sessionProvider ?? settings.provider }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ask about this item").font(.system(size: 22, weight: .bold))
                    Text(item.title).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer()
                Button("Close chat") { request?.cancel(); dismiss() }.buttonStyle(PaperButton())
            }
            HStack {
                Label(activeProvider.title, systemImage: "sparkles").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Connection…") { showSettings = true }.buttonStyle(PaperButton(compact: true)).disabled(!messages.isEmpty || busy)
            }
            HStack {
                Toggle("Include attached notes", isOn: $includeNotes).font(.system(size: 12)).disabled(!messages.isEmpty || busy)
                Spacer()
                Button("Preview what is sent") { showContext.toggle() }.buttonStyle(.link).font(.system(size: 12))
            }
            if showContext {
                ScrollView { Text((try? AIRequest.context(item, includeNotes: includeNotes)) ?? "Item exceeds the request limit.")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .padding(12).frame(height: 130).background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Make something useful from what you saved.").font(.system(size: 17, weight: .semibold))
                                Text("Summarize a transcript, pull out action items, or ask a follow-up. Only this item’s title, text, optional attached notes, and this chat are sent. Audio files are not uploaded.")
                                    .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                                HStack {
                                    Button("Summarize") { prompt = "Summarize this item clearly and concisely." }
                                    Button("Bullet points") { prompt = "Turn this item into concise bullet points, including any decisions and action items." }
                                }.buttonStyle(PaperButton(compact: true))
                            }.padding(20)
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(message.role == "user" ? "You" : "AI response").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.muted)
                                Text(message.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                if message.role == "assistant" {
                                    HStack {
                                        Button("Copy") { copyToClipboard(message.text) }
                                        Button(saved.contains(message.id) ? "Saved as note" : "Save as note") {
                                            if store.addNote(to: item.id, text: message.text) { saved.insert(message.id) }
                                            else { error = store.errorMessage }
                                        }.disabled(saved.contains(message.id))
                                    }.buttonStyle(PaperButton(compact: true))
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Palette.canvas : Palette.paper)
                                .clipShape(RoundedRectangle(cornerRadius: 6)).id(message.id)
                        }
                        if busy { ProgressView("Thinking…").font(.system(size: 12)).id("progress") }
                    }.padding(4)
                }.onChange(of: messages.count) { _, _ in if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            ContentEditor(text: $prompt, minimum: 75, label: "Ask AI about this item").frame(height: 95).disabled(busy)
            HStack {
                Text("Sent to your selected provider. Save answers as notes to keep them.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                if busy { Button("Stop") { request?.cancel() }.buttonStyle(PaperButton()) }
                else {
                    Button("Send", action: send).buttonStyle(PaperButton(primary: true)).keyboardShortcut(.return, modifiers: .command)
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(24).frame(width: 720, height: 740).background(Palette.canvas).foregroundStyle(Palette.ink)
            .onAppear { prompt = initialPrompt }
            .onDisappear { request?.cancel() }
            .sheet(isPresented: $showSettings) {
                VStack { AISettingsView(); Button("Done") { showSettings = false }.buttonStyle(PaperButton()).padding(.bottom, 20) }
                    .frame(width: 540, height: 460).background(Palette.canvas).foregroundStyle(Palette.ink)
            }
    }
    private func send() {
        let question = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        do {
            let context = try AIRequest.context(item, includeNotes: includeNotes)
            if sessionProvider == nil { sessionProvider = settings.provider; sessionModel = settings.model }
            let message = AIMessage(role: "user", text: question)
            messages.append(message)
            prompt = ""; error = nil; busy = true
            let history = messages, provider = activeProvider, model = sessionModel
            request = Task {
                do {
                    let response = try await AIService.reply(provider: provider, model: model, context: context, messages: history)
                    try Task.checkCancellation()
                    messages.append(AIMessage(role: "assistant", text: response))
                } catch {
                    messages.removeAll { $0.id == message.id }
                    if prompt.isEmpty { prompt = question }
                    self.error = Task.isCancelled ? "Request stopped. Your item is unchanged." : error.localizedDescription
                    if messages.isEmpty { sessionProvider = nil }
                }
                busy = false
            }
        } catch { self.error = error.localizedDescription }
    }
}
