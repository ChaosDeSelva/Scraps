import AppKit
import SwiftUI

@main struct RenderUI {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("scraps-render-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScrapStore(url: directory.appendingPathComponent("preview.sqlite"))
        let examples: [(String, String, String, ItemKind, String)] = [
            ("An idea worth keeping", "Capture first. Add the context when you come back.\n\nThe original and your own thoughts should always stay together.", "ideas, product", .note, "Try this with notes from the next planning session."),
            ("A small checklist for the demo", "Check the local data.\nWalk through the capture flow.\nLeave time for questions.", "work, follow-up", .note, "Keep the demo focused on saving and finding things."),
            ("Start the local workspace", "cd ~/Code/my-project\nnpm run dev\n\n# Open the local app after startup.", "dev, project-name, follow-up", .snippet, "Use this for the next demo. Check the local data before starting.")
        ]
        for example in examples {
            var draft = CaptureDraft()
            draft.title = example.0
            draft.content = example.1
            draft.tags = example.2
            draft.kind = example.3
            draft.note = example.4
            draft.source = "Personal workspace"
            _ = store.capture(draft)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        store.draft.title = "A useful command"
        store.draft.content = "npm run dev"
        store.draft.tags = "dev, project-name"
        for (name, appearance) in [("", NSAppearance.Name.aqua), ("-dark", .darkAqua)] {
            app.appearance = NSAppearance(named: appearance)
            try render(LibraryView(store: store, capture: {}), size: NSSize(width: 1200, height: 800), appearance: appearance, to: output.appendingPathComponent("library\(name).png"))
            try render(LibraryView(store: store, capture: {}), size: NSSize(width: 1040, height: 680), appearance: appearance, to: output.appendingPathComponent("library-minimum\(name).png"))
            try render(CaptureView(store: store, openLibrary: {}, didSave: {}), size: NSSize(width: 470, height: 620), appearance: appearance, to: output.appendingPathComponent("capture\(name).png"))
            try render(SettingsView(), size: NSSize(width: 480, height: 350), appearance: appearance, to: output.appendingPathComponent("settings\(name).png"))
            if let item = store.selectedItem {
                try render(EditItemView(store: store, item: item), size: NSSize(width: 690, height: 670), appearance: appearance, to: output.appendingPathComponent("edit-item\(name).png"))
                if let annotation = item.annotations.first {
                    try render(EditAnnotationView(store: store, itemID: item.id, annotation: annotation), size: NSSize(width: 570, height: 340), appearance: appearance, to: output.appendingPathComponent("edit-note\(name).png"))
                }
            }
        }
        print("Rendered library, quick capture and item editor in light and dark appearances.")
    }

    @MainActor static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: appearance)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No render buffer") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG representation") }
        try png.write(to: url)
        print("\(url.lastPathComponent): \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
    }
}
