import SwiftUI
import AppKit

struct LibraryView: View {
    @ObservedObject var store: ScrapStore
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var shortcuts = ShortcutSettings.shared
    let capture: () -> Void
    var settings: () -> Void = {}
    var record: () -> Void = {}
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(spacing: 0) {
                    itemList.frame(width: 300)
                    Rectangle().fill(Palette.line).frame(width: 1)
                    if let item = store.selectedItem {
                        DetailView(store: store, item: item).id(item.id)
                    } else { emptyDetail }
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 670)
        .background(Palette.canvas).foregroundStyle(Palette.ink)
        .onReceive(NotificationCenter.default.publisher(for: .scrapsFocusSearch)) { _ in searchFocused = true }
        .alert("Couldn’t save your changes", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Your existing library has been preserved.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                BrandMark()
                VStack(alignment: .leading, spacing: 0) {
                    Text("Scraps").font(.system(size: 25, weight: .heavy, design: .rounded))
                    Text("KEEP THE USEFUL BITS").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.9).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 22).padding(.top, 32).padding(.bottom, 30)
            Button(action: capture) {
                HStack {
                    Image(systemName: "plus"); Text("Quick capture"); Spacer()
                }
            }.buttonStyle(PaperButton(primary: true)).padding(.horizontal, 16).padding(.bottom, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Library").padding(.leading, 14).padding(.bottom, 9)
                    navRow(.all, symbol: "tray.full")
                    navRow(.snippets, symbol: "chevron.left.forwardslash.chevron.right")
                    navRow(.notes, symbol: "note.text")
                    navRow(.questions, symbol: "questionmark.circle")
                    navRow(.reminders, symbol: "bell")
                    navRow(.recordings, symbol: "waveform")
                    navRow(.other, symbol: "square.grid.2x2")
                    navRow(.pinned, symbol: "pin")
                    Eyebrow(text: "Tags").padding(.leading, 14).padding(.top, 27).padding(.bottom, 9)
                    if store.tags.isEmpty {
                        Text("Tags you add will live here.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    ForEach(store.tags, id: \.self) { tag in navRow(.tag(tag), symbol: "number") }
                }.padding(.horizontal, 12)
            }
            VStack(alignment: .leading, spacing: 14) {
                navRow(.trash, symbol: "trash")
                Rectangle().fill(Palette.line).frame(height: 1)
                Menu {
                    Picker("Appearance", selection: $appearance.choice) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(appearance.choice.title, systemImage: appearance.choice.symbol)
                        .font(.system(size: 12)).foregroundStyle(Palette.body)
                }
                .menuStyle(.borderlessButton).padding(.horizontal, 10)
                .help("Appearance").accessibilityLabel("Appearance: " + appearance.choice.title)
                Button(action: settings) { Label("Settings…", systemImage: "gearshape") }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.body).padding(.horizontal, 10)
                HStack(spacing: 7) {
                    Circle().fill(Palette.green).frame(width: 6, height: 6)
                    Text("Stored on this Mac").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.body)
                }.padding(.horizontal, 10)
            }.padding(12).padding(.bottom, 10)
        }.background(Palette.sidebar)
    }

    private func navRow(_ filter: LibraryFilter, symbol: String) -> some View {
        let title: String
        if case .tag(let tag) = filter { title = tag } else { title = filter.title }
        return Button { store.filter = filter; store.selectedID = nil } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol).font(.system(size: 14)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: store.filter == filter ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                Text(String(store.count(filter))).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink).padding(.horizontal, 12).frame(height: 39)
            .background(store.filter == filter ? Palette.paper : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(store.filter == filter ? Palette.line : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
            .accessibilityAddTraits(store.filter == filter ? .isSelected : [])
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search all items, notes, and tags…", text: $store.query)
                    .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
                    .accessibilityLabel("Search library")
                if !store.query.isEmpty {
                    Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                } else { Text("⌘F").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 12).frame(height: 37)
                .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
            Button(action: record) { Label("Record", systemImage: "mic") }.buttonStyle(PaperButton(compact: true))
            Menu {
                Button("Newest saved") { store.sortByEdited = false }
                Button("Recently edited") { store.sortByEdited = true }
            } label: { Label(store.sortByEdited ? "Recently edited" : "Newest first", systemImage: "arrow.up.arrow.down").font(.system(size: 12)) }
                .menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 24).frame(height: 76)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.filter.title).font(.system(size: 21, weight: .bold)).lineLimit(1)
                Spacer()
                Text(String(store.visibleItems.count)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 22).padding(.top, 25).padding(.bottom, 18)
            if store.visibleItems.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.query.isEmpty ? "Nothing here yet." : "No matches here.").font(.system(size: 14, weight: .semibold))
                    Text(store.query.isEmpty ? "Your saved items will appear here." : "Try another word or choose All items.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    if !store.query.isEmpty {
                        Button("Clear search") { store.query = "" }.buttonStyle(PaperButton(compact: true)).padding(.top, 4)
                    }
                }.padding(22)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.visibleItems) { item in
                            itemRow(item)
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 16)
                }
            }
            HStack {
                Image(systemName: "text.magnifyingglass")
                Text("Search includes your annotations")
            }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(17)
        }.background(Palette.canvas)
    }

    private func itemRow(_ item: Scrap) -> some View {
        let selected = store.selectedItem?.id == item.id
        return Button { store.selectedID = item.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(item.kind.label.uppercased(), systemImage: item.kind.symbol)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.6)
                    Spacer()
                    if item.isPinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                }.foregroundStyle(Palette.muted)
                Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(item.preview).font(.system(size: 12, design: item.kind == .snippet ? .monospaced : .default))
                    .foregroundStyle(Palette.muted).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    Text(item.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                    if !item.tags.isEmpty { Text("# " + item.tags[0]).lineLimit(1) }
                    Spacer(minLength: 0)
                    if !item.annotations.isEmpty { Label(String(item.annotations.count), systemImage: "text.bubble") }
                }.font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(15)
                .background(selected ? Palette.paper : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Palette.ink.opacity(0.55) : Palette.line.opacity(0.45), lineWidth: 1))
                .overlay(alignment: .leading) {
                    if selected { RoundedRectangle(cornerRadius: 2).fill(Palette.yellow).frame(width: 3).padding(.vertical, 12) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var emptyDetail: some View {
        VStack(spacing: 19) {
            BrandMark(size: 62)
            VStack(spacing: 9) {
                Text(store.filter == .trash ? "A little room for second thoughts." : "Keep it. Give it context.")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                Text(store.filter == .trash ? "Items moved to Trash can be restored here." : "Commands, ideas, and things worth coming back to.\nSave your first item from the menu bar.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted).multilineTextAlignment(.center).lineSpacing(5)
            }
            if store.filter != .trash {
                Button(action: capture) { Label("Capture something", systemImage: "plus") }.buttonStyle(PaperButton(primary: true))
                Text(store.shortcutAvailable ? "\(shortcuts.shortcut.displayName) works from any app" : "Click the tray icon in your menu bar")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted)
            }
        }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
    }
}

struct DetailView: View {
    @ObservedObject var store: ScrapStore
    let item: Scrap
    @State private var editing = false
    @State private var editingNote: Annotation?
    @State private var copied = false
    @State private var aiPrompt: String?

    private var note: String { store.annotationDrafts[item.id] ?? "" }
    private var noteBinding: Binding<String> {
        Binding(get: { store.annotationDrafts[item.id] ?? "" }, set: { store.annotationDrafts[item.id] = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(item.kind.label, systemImage: item.kind.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                Spacer()
                if item.trashedAt == nil {
                    Menu {
                        Button("Summarize") { aiPrompt = "Summarize this item clearly and concisely." }
                        Button("Bullet points") { aiPrompt = "Turn this item into concise bullet points, including any decisions and action items." }
                        Button("Chat about this item") { aiPrompt = "" }
                    } label: { Label("Ask AI", systemImage: "sparkles").font(.system(size: 12)) }
                        .menuStyle(.borderlessButton).fixedSize()
                    IconButton(symbol: item.isPinned ? "pin.fill" : "pin", label: item.isPinned ? "Unpin item" : "Pin item", active: item.isPinned) { store.togglePin(item.id) }
                    IconButton(symbol: "square.and.pencil", label: "Edit item") { editing = true }
                    IconButton(symbol: "trash", label: "Move to Trash") { store.trash(item.id) }
                } else {
                    Button("Restore item") { store.restore(item.id) }.buttonStyle(PaperButton(compact: true))
                }
            }.padding(.horizontal, 28).padding(.vertical, 14)
            Rectangle().fill(Palette.line.opacity(0.6)).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(item.title).font(.system(size: 27, weight: .bold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        VStack(alignment: .leading, spacing: 5) {
                            Label("Saved " + item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            if item.updatedAt.timeIntervalSince(item.createdAt) > 1 {
                                Label("Edited " + item.updatedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                            }
                        }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                        if !item.tags.isEmpty {
                            FlowLayout {
                                ForEach(item.tags, id: \.self) { tag in
                                    Button { store.filter = .tag(tag) } label: { TagChip(text: tag) }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if let recording = item.recording {
                        RecordingAttachmentView(store: store, item: item, attachment: recording)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: item.recording == nil ? "Original content" : "Transcript")
                            Spacer()
                            Button {
                                copyToClipboard(item.content)
                                copied = true
                            } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                                .buttonStyle(PaperButton(compact: true))
                        }
                        Text(item.content.isEmpty && item.recording != nil ? "Create a transcript above, or use Edit item to add your own text." : item.content)
                            .font(.system(size: 13, design: item.kind == .snippet ? .monospaced : .default))
                            .lineSpacing(5).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            .padding(20)
                            .foregroundStyle(item.kind == .snippet ? Color(hex: 0xEFF0E7) : Palette.ink)
                            .background(item.kind == .snippet ? Palette.code : Palette.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        if !item.source.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "link")
                                Text(item.source).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text("Your notes").font(.system(size: 18, weight: .bold))
                            Text(String(item.annotations.count)).font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Palette.canvas).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if item.annotations.isEmpty {
                            Text("The why, the gotcha, the next step. Keep it with the original.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(item.annotations) { annotation in
                            HStack(alignment: .top, spacing: 12) {
                                RoundedRectangle(cornerRadius: 1).fill(Palette.yellow).frame(width: 3)
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(annotation.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                                        if annotation.updatedAt.timeIntervalSince(annotation.createdAt) > 1 { Text("· edited").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                                        Spacer()
                                        if item.trashedAt == nil {
                                            Button { editingNote = annotation } label: { Image(systemName: "pencil").font(.system(size: 11)) }
                                                .buttonStyle(.plain).help("Edit annotation").accessibilityLabel("Edit annotation")
                                        }
                                    }
                                    Text(annotation.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.fixedSize(horizontal: false, vertical: true)
                        }
                        if item.trashedAt == nil {
                            VStack(alignment: .trailing, spacing: 9) {
                                ZStack(alignment: .topLeading) {
                                    ContentEditor(text: noteBinding, minimum: 90, label: "Add an annotation")
                                    if note.isEmpty {
                                        Text("Add a little context…").font(.system(size: 13)).foregroundStyle(Palette.muted)
                                            .padding(.leading, 15).padding(.top, 17).allowsHitTesting(false)
                                    }
                                }
                                Button { if store.addNote(to: item.id, text: note) { store.annotationDrafts[item.id] = nil } } label: {
                                    Label("Add note", systemImage: "plus")
                                }.buttonStyle(PaperButton()).disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }.padding(28)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
            .sheet(isPresented: Binding(get: { aiPrompt != nil }, set: { if !$0 { aiPrompt = nil } })) {
                AIChatView(store: store, item: item, initialPrompt: aiPrompt ?? "")
            }
            .sheet(isPresented: $editing) { EditItemView(store: store, item: item) }
            .sheet(item: $editingNote) { annotation in EditAnnotationView(store: store, itemID: item.id, annotation: annotation) }
            .onChange(of: item.content) { _, _ in copied = false }
    }
}

struct EditAnnotationView: View {
    @ObservedObject var store: ScrapStore
    let itemID: UUID
    let annotation: Annotation
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(store: ScrapStore, itemID: UUID, annotation: Annotation) {
        self.store = store
        self.itemID = itemID
        self.annotation = annotation
        _text = State(initialValue: annotation.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit your note").font(.system(size: 22, weight: .bold))
            ContentEditor(text: $text, minimum: 180, label: "Annotation")
            if let error = store.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PaperButton()).keyboardShortcut(.cancelAction)
                Button("Save note") { if store.editNote(itemID: itemID, noteID: annotation.id, text: text) { dismiss() } }
                    .buttonStyle(PaperButton(primary: true)).keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 570, height: 340).background(Palette.canvas)
            .foregroundStyle(Palette.ink).interactiveDismissDisabled()
    }
}

extension Notification.Name {
    static let scrapsFocusSearch = Notification.Name("ScrapsFocusSearch")
}
