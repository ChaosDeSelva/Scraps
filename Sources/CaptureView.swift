import SwiftUI
import AppKit

struct CaptureView: View {
    @ObservedObject var store: ScrapStore
    let openLibrary: () -> Void
    let didSave: () -> Void
    @State private var extraContext = false
    @State private var choosingKind = false
    @FocusState private var contentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("A place for the useful bits.").font(.system(size: 17, weight: .bold))
                    Text("Quick capture").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                IconButton(symbol: "rectangle.expand.vertical", label: "Open library", action: openLibrary)
            }.padding(22)
            Rectangle().fill(Palette.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            kindPicker
                            Spacer()
                            Button { if let value = NSPasteboard.general.string(forType: .string) { store.draft.content += value } } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }.buttonStyle(PaperButton(compact: true))
                        }
                        if choosingKind { kindOptions }
                    }
                    PaperField(title: "Title · optional", placeholder: "A name you’ll remember", text: $store.draft.title)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(store.draft.kind.contentLabel).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if store.draft.content.isEmpty { Text("Paste it here. Sort it later.").font(.system(size: 11)).foregroundStyle(Palette.muted) }
                        }
                        ContentEditor(text: $store.draft.content, code: store.draft.kind == .snippet, minimum: 165)
                            .focused($contentFocused)
                    }
                    PaperField(title: "Tags · optional", placeholder: "dev, project-name, follow-up", text: $store.draft.tags)
                    DisclosureGroup("Add a note or source", isExpanded: $extraContext) {
                        VStack(alignment: .leading, spacing: 12) {
                            PaperField(title: "Your note", placeholder: "Why are you keeping this?", text: $store.draft.note)
                            PaperField(title: "Source", placeholder: "A URL, app, or reference", text: $store.draft.source)
                        }.padding(.top, 10)
                    }.font(.system(size: 12, weight: .medium)).tint(Palette.body)
                    if let error = store.errorMessage {
                        Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled)
                    }
                }.padding(22)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Only on this Mac", systemImage: "internaldrive").font(.system(size: 11, weight: .medium))
                    Text("Saved date added automatically").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button(action: save) { HStack(spacing: 12) { Text("Save item"); Text("⌘↵").opacity(0.6) } }
                    .buttonStyle(PaperButton(primary: true)).keyboardShortcut(.return, modifiers: .command)
                    .disabled(!store.draft.canSave || !store.ready)
            }.padding(22)
        }
        .frame(width: 470, height: 620).background(Palette.canvas)
        .foregroundStyle(Palette.ink)
        .onAppear { contentFocused = true }
    }

    private var kindPicker: some View {
        Button { choosingKind.toggle() } label: {
            HStack(spacing: 9) {
                Label(store.draft.kind.label, systemImage: store.draft.kind.symbol)
                Spacer(minLength: 12)
                Image(systemName: choosingKind ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
            }.frame(width: 140)
        }
        .buttonStyle(PaperButton(compact: true))
        .accessibilityLabel("Item type: " + store.draft.kind.label)
        .accessibilityValue(choosingKind ? "Expanded" : "Collapsed")
    }

    private var kindOptions: some View {
        VStack(spacing: 2) {
            ForEach(ItemKind.allCases) { kind in
                Button {
                    store.draft.kind = kind
                    choosingKind = false
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: kind.symbol).frame(width: 18)
                        Text(kind.label)
                        Spacer()
                        if store.draft.kind == kind { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                    }
                    .font(.system(size: 13)).padding(.horizontal, 12).frame(height: 34)
                    .background(store.draft.kind == kind ? Palette.selected : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(store.draft.kind == kind ? .isSelected : [])
            }
        }.padding(5).background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
    }

    private func save() {
        guard store.capture(store.draft) != nil else { return }
        store.draft = CaptureDraft()
        extraContext = false
        choosingKind = false
        didSave()
    }
}

struct EditItemView: View {
    @ObservedObject var store: ScrapStore
    let itemID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CaptureDraft
    @State private var confirmDiscard = false
    private let original: CaptureDraft

    init(store: ScrapStore, item: Scrap) {
        self.store = store
        itemID = item.id
        let draft = CaptureDraft(item: item)
        original = draft
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool {
        draft.title != original.title || draft.content != original.content || draft.tags != original.tags || draft.source != original.source || draft.kind != original.kind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Edit item").font(.system(size: 23, weight: .bold))
                Spacer()
                Picker("Type", selection: $draft.kind) {
                    ForEach(ItemKind.allCases) { Text($0.label).tag($0) }
                }.frame(width: 150)
            }
            PaperField(title: "Title", placeholder: "Untitled", text: $draft.title)
            ContentEditor(text: $draft.content, code: draft.kind == .snippet, minimum: 260)
            PaperField(title: "Tags", placeholder: "Separate tags with commas", text: $draft.tags)
            PaperField(title: "Source · optional", placeholder: "A URL, app, or reference", text: $draft.source)
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.system(size: 12)) }
            HStack {
                Text("Your saved date and notes stay with this item.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel") { if hasChanges { confirmDiscard = true } else { dismiss() } }
                    .buttonStyle(PaperButton()).keyboardShortcut(.cancelAction)
                Button("Save changes") { if store.update(itemID, draft: draft) { dismiss() } }
                    .buttonStyle(PaperButton(primary: true)).keyboardShortcut(.return, modifiers: .command).disabled(!draft.canSave && store.item(itemID)?.recording == nil)
            }
        }.padding(28).frame(width: 690, height: 670).background(Palette.canvas)
            .foregroundStyle(Palette.ink).interactiveDismissDisabled()
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
    }
}
