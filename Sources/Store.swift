import Foundation
import Combine

@MainActor final class ScrapStore: ObservableObject {
    @Published private(set) var items: [Scrap] = []
    @Published var selectedID: UUID?
    @Published var filter: LibraryFilter = .all
    @Published var query = ""
    @Published var sortByEdited = false
    @Published var draft = CaptureDraft()
    @Published var annotationDrafts: [UUID: String] = [:]
    @Published var shortcutAvailable = true
    @Published var errorMessage: String?
    @Published private(set) var ready = false
    private var database: Database?
    let databaseURL: URL

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scraps", isDirectory: true).appendingPathComponent("Scraps.sqlite")
    }

    init(url: URL = ScrapStore.defaultURL) {
        databaseURL = url
        do {
            let db = try Database(url: url)
            items = try db.load()
            database = db
            ready = true
        } catch { errorMessage = error.localizedDescription }
    }

    var visibleItems: [Scrap] {
        items.filter { filter.includes($0) && $0.matches(query) }.sorted {
            let left = sortByEdited ? $0.updatedAt : $0.createdAt
            let right = sortByEdited ? $1.updatedAt : $1.createdAt
            return left == right ? $0.id.uuidString < $1.id.uuidString : left > right
        }
    }

    var selectedItem: Scrap? {
        visibleItems.first(where: { $0.id == selectedID }) ?? visibleItems.first
    }

    var tags: [String] {
        Array(Set(items.filter { $0.trashedAt == nil }.flatMap(\.tags))).sorted()
    }

    func count(_ filter: LibraryFilter) -> Int { items.filter { filter.includes($0) }.count }

    func item(_ id: UUID) -> Scrap? { items.first { $0.id == id } }

    @discardableResult func capture(_ draft: CaptureDraft) -> UUID? {
        guard draft.canSave else { return nil }
        let item = draft.makeItem()
        guard persist(item) else { return nil }
        filter = .all
        query = ""
        selectedID = item.id
        return item.id
    }

    @discardableResult func update(_ id: UUID, draft: CaptureDraft) -> Bool {
        guard draft.canSave, var item = item(id) else { return false }
        let revised = draft.makeItem()
        item.title = revised.title
        item.content = revised.content
        item.kind = revised.kind
        item.tags = revised.tags
        item.source = revised.source
        item.updatedAt = Date()
        return persist(item)
    }

    @discardableResult func addNote(to id: UUID, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var item = item(id) else { return false }
        item.annotations.append(Annotation(text: clean))
        item.updatedAt = Date()
        return persist(item)
    }

    @discardableResult func editNote(itemID: UUID, noteID: UUID, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var item = item(itemID), let index = item.annotations.firstIndex(where: { $0.id == noteID }) else { return false }
        item.annotations[index].text = clean
        item.annotations[index].updatedAt = Date()
        item.updatedAt = Date()
        return persist(item)
    }

    func togglePin(_ id: UUID) {
        guard var item = item(id) else { return }
        item.isPinned.toggle()
        _ = persist(item)
    }

    func trash(_ id: UUID) {
        guard var item = item(id) else { return }
        item.trashedAt = Date()
        _ = persist(item)
    }

    func restore(_ id: UUID) {
        guard var item = item(id) else { return }
        item.trashedAt = nil
        _ = persist(item)
    }

    private func persist(_ item: Scrap) -> Bool {
        guard let database, ready else {
            errorMessage = "The library is unavailable. Quit and reopen Scraps after checking access to its data folder."
            return false
        }
        do {
            try database.save(item)
            errorMessage = nil
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item }
            else { items.append(item) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
