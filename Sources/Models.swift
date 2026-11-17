import Foundation

enum ItemKind: String, Codable, CaseIterable, Identifiable {
    case snippet, note, question, reminder, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .snippet: return "Snippet"
        case .note: return "Note"
        case .question: return "Question"
        case .reminder: return "Reminder"
        case .other: return "Other"
        }
    }
    var symbol: String {
        switch self {
        case .snippet: return "chevron.left.forwardslash.chevron.right"
        case .note: return "note.text"
        case .question: return "questionmark.circle"
        case .reminder: return "bell"
        case .other: return "square.grid.2x2"
        }
    }
    var contentLabel: String { self == .other ? "Your content" : "Your " + label.lowercased() }
}

struct Annotation: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    var updatedAt = Date()
}

struct Scrap: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var content: String
    var kind: ItemKind
    var tags: [String]
    var source: String
    var createdAt = Date()
    var updatedAt = Date()
    var isPinned = false
    var trashedAt: Date?
    var annotations: [Annotation] = []
    var recording: RecordingAttachment?

    var preview: String {
        content.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let haystack = ([title, content, source] + tags + annotations.map(\.text)).joined(separator: " ")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.range(of: String($0), options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

struct CaptureDraft {
    var title = ""
    var content = ""
    var kind: ItemKind = .snippet
    var tags = ""
    var source = ""
    var note = ""

    var canSave: Bool { !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func parseTags(_ input: String) -> [String] {
        var seen = Set<String>()
        return input.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func makeItem(now: Date = Date()) -> Scrap {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? kind.label
        var item = Scrap(title: cleanTitle.isEmpty ? String(fallback.prefix(90)) : cleanTitle,
                         content: content, kind: kind, tags: Self.parseTags(tags),
                         source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                         createdAt: now, updatedAt: now)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNote.isEmpty {
            item.annotations = [Annotation(text: cleanNote, createdAt: now, updatedAt: now)]
        }
        return item
    }

    init() {}
    init(item: Scrap) {
        title = item.title
        content = item.content
        kind = item.kind
        tags = item.tags.joined(separator: ", ")
        source = item.source
    }
}

enum LibraryFilter: Hashable {
    case all, snippets, notes, questions, reminders, recordings, other, pinned, trash, tag(String)

    var title: String {
        switch self {
        case .all: return "All items"
        case .snippets: return "Snippets"
        case .notes: return "Notes"
        case .questions: return "Questions"
        case .reminders: return "Reminders"
        case .recordings: return "Recordings"
        case .other: return "Other"
        case .pinned: return "Pinned"
        case .trash: return "Trash"
        case .tag(let name): return "# \(name)"
        }
    }

    func includes(_ item: Scrap) -> Bool {
        if self == .trash { return item.trashedAt != nil }
        guard item.trashedAt == nil else { return false }
        switch self {
        case .all: return true
        case .snippets: return item.kind == .snippet
        case .notes: return item.kind == .note
        case .questions: return item.kind == .question
        case .reminders: return item.kind == .reminder
        case .recordings: return item.recording != nil
        case .other: return item.kind == .other
        case .pinned: return item.isPinned
        case .tag(let name): return item.tags.contains(name)
        case .trash: return false
        }
    }
}


enum RecordingSource: String, Codable, CaseIterable, Identifiable {
    case microphone, system, both
    var id: String { rawValue }
    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .system: return "Mac audio"
        case .both: return "Microphone + Mac audio"
        }
    }
}

struct RecordingAttachment: Codable, Equatable {
    var id: UUID
    var duration: TimeInterval
    var source: RecordingSource
}
