import Foundation
import SQLite3

enum TestFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): return message } }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw TestFailure.failed(message) }
}

func sql(_ url: URL, _ command: String) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw TestFailure.failed("Test database could not open") }
    defer { sqlite3_close(handle) }
    guard sqlite3_exec(handle, command, nil, nil, nil) == SQLITE_OK else {
        throw TestFailure.failed(String(cString: sqlite3_errmsg(handle)))
    }
}

@main struct StoreTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scraps-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.sqlite")
        let store = ScrapStore(url: url)
        try expect(store.ready && store.items.isEmpty, "New library must start empty")
        try expect(store.capture(CaptureDraft()) == nil, "Blank capture must not create an item")

        var draft = CaptureDraft()
        draft.content = "  SELECT 'café';\n\n  // 🧪 literal content, including trailing spaces  \n"
        draft.title = "Database example"
        draft.tags = "#Dev, project alpha, DEV, , #sql"
        draft.source = "https://example.com/reference"
        draft.note = "Check staging before using this."
        guard let id = store.capture(draft), let saved = store.item(id) else { throw TestFailure.failed("Capture failed") }
        try expect(saved.content == draft.content, "Capture must preserve original whitespace and Unicode")
        try expect(saved.tags == ["dev", "project alpha", "sql"], "Tags must normalize without duplicate case variants")
        try expect(saved.annotations.count == 1, "Initial annotation must stay separate from content")
        try expect(saved.matches("DATABASE café staging #not-present") == false, "Search requires all terms")
        try expect(saved.matches("database cafe staging") == true, "Search must include annotations and ignore case/diacritics")
        try expect(saved.matches("project alpha") == true, "Multi-word tag must be searchable")
        print("PASS capture, content fidelity, tag normalization, multi-field search")

        try expect(store.addNote(to: id, text: "  Use the replica for reads.  "), "Annotation save failed")
        let firstDate = store.item(id)!.createdAt
        let annotationID = store.item(id)!.annotations[1].id
        try expect(store.editNote(itemID: id, noteID: annotationID, text: "Use the reporting replica."), "Annotation edit failed")
        var edit = CaptureDraft(item: store.item(id)!)
        edit.title = "Read-only query"
        edit.content = "SELECT * FROM example WHERE name = 'quoted';\n"
        edit.tags = "db, reports"
        try expect(store.update(id, draft: edit), "Item edit failed")
        let edited = store.item(id)!
        try expect(edited.createdAt == firstDate, "Editing must preserve saved date")
        try expect(edited.annotations.count == 2 && edited.annotations[1].id == annotationID, "Editing original must preserve annotation identity")
        try expect(edited.annotations[1].text == "Use the reporting replica.", "Annotation edit must persist")
        try expect(edited.tags == ["db", "reports"], "Tag edits must replace old tags")
        print("PASS item and annotation edits preserve dates and context")

        store.query = "reporting"
        try expect(store.visibleItems.count == 1, "Annotation text must locate the parent snippet")
        store.filter = .notes
        try expect(store.visibleItems.isEmpty, "Kind filter must combine with search")
        store.filter = .tag("db")
        try expect(store.visibleItems.count == 1, "Tag filter must combine with search")
        store.togglePin(id)
        store.filter = .pinned
        try expect(store.visibleItems.count == 1, "Pinned view must include pinned items")
        store.trash(id)
        try expect(store.visibleItems.isEmpty && store.tags.isEmpty, "Trashed items must leave active filters and tags")
        store.filter = .trash
        try expect(store.visibleItems.count == 1, "Trash must retain searchable content")
        store.restore(id)
        store.filter = .all
        try expect(store.visibleItems.count == 1, "Restore must recover the same item")
        print("PASS search, filter, pin, trash, and restore")

        let reopened = ScrapStore(url: url)
        try expect(reopened.ready && reopened.item(id) == store.item(id), "Reopening must preserve content, annotations, tags, dates and pin")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        try expect(permissions?.intValue == 0o600, "Database should be readable only by its owner")
        print("PASS SQLite reopen round trip and database permissions")

        try sql(url, "CREATE TRIGGER fail_update BEFORE UPDATE ON scraps BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END;")
        let before = store.item(id)
        edit.title = "Must not appear"
        try expect(!store.update(id, draft: edit), "Failed disk write must report failure")
        try expect(store.item(id) == before, "Failed disk write must not change visible content")
        try expect(store.errorMessage != nil, "Failed save must surface an error")
        let afterFailure = ScrapStore(url: url)
        try expect(afterFailure.item(id) == before, "Failed save must not damage stored content")
        print("PASS failed saves preserve both visible and stored content")

        let future = directory.appendingPathComponent("future.sqlite")
        try sql(future, "PRAGMA user_version = 99")
        let futureStore = ScrapStore(url: future)
        try expect(!futureStore.ready && futureStore.errorMessage != nil, "Newer schema must not be overwritten")
        try expect(futureStore.capture(draft) == nil, "Unavailable library must refuse saves")

        let corrupt = directory.appendingPathComponent("corrupt.sqlite")
        try sql(corrupt, "CREATE TABLE scraps(id TEXT PRIMARY KEY, payload BLOB); INSERT INTO scraps VALUES('bad', X'626164'); PRAGMA user_version=1;")
        let corruptStore = ScrapStore(url: corrupt)
        try expect(!corruptStore.ready && corruptStore.errorMessage != nil, "Unreadable content must not be silently discarded")
        try expect(corruptStore.capture(draft) == nil, "Corrupt library must not accept replacement content")
        print("PASS newer and corrupt libraries fail closed without replacement")

        let typesURL = directory.appendingPathComponent("types.sqlite")
        let typesStore = ScrapStore(url: typesURL)
        let typeCases: [(ItemKind, LibraryFilter)] = [
            (.snippet, .snippets), (.note, .notes), (.question, .questions),
            (.reminder, .reminders), (.other, .other)
        ]
        for (kind, _) in typeCases {
            var typed = CaptureDraft()
            typed.kind = kind
            typed.content = "Saved \(kind.label) with café and \"quotes\""
            typed.note = "Annotation remains searchable"
            try expect(typesStore.capture(typed) != nil, "Could not save \(kind.label)")
        }
        let reopenedTypes = ScrapStore(url: typesURL)
        for (kind, filter) in typeCases {
            reopenedTypes.filter = filter
            reopenedTypes.query = "cafe searchable"
            try expect(reopenedTypes.visibleItems.count == 1 && reopenedTypes.visibleItems[0].kind == kind,
                       "\(kind.label) must reopen in its own searchable filter")
        }
        let existingSnippet = reopenedTypes.items.first { $0.kind == .snippet }!
        var changeType = CaptureDraft(item: existingSnippet)
        changeType.kind = .reminder
        try expect(reopenedTypes.update(existingSnippet.id, draft: changeType), "Changing an existing item type failed")
        let changedType = ScrapStore(url: typesURL).item(existingSnippet.id)!
        try expect(changedType.kind == .reminder && changedType.createdAt == existingSnippet.createdAt && changedType.annotations == existingSnippet.annotations,
                   "Changing type must preserve the saved date and annotations after reopening")
        print("PASS all five item types persist, filter, search, and preserve context when changed")
        print("All persistence and behavior checks passed.")
    }
}
