import AppKit
import Carbon
import Combine

struct CaptureShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let key: String

    static let standard = CaptureShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), key: "Space")
    private static let allowedModifiers = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    var isValid: Bool {
        keyCode < 128 && modifiers & ~Self.allowedModifiers == 0 &&
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 &&
        !key.isEmpty && key.count <= 20 && key.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    var displayName: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    static func recorded(from event: NSEvent) -> CaptureShortcut? {
        var modifiers: UInt32 = 0
        for (flag, carbon) in [(NSEvent.ModifierFlags.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)] {
            if event.modifierFlags.contains(flag) { modifiers |= UInt32(carbon) }
        }
        let special: [UInt16: String] = [
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return", UInt16(kVK_Tab): "Tab",
            UInt16(kVK_Delete): "Delete", UInt16(kVK_ForwardDelete): "Forward Delete",
            UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "Home", UInt16(kVK_End): "End", UInt16(kVK_PageUp): "Page Up", UInt16(kVK_PageDown): "Page Down",
            UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
        ]
        guard let key = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() else { return nil }
        let shortcut = CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        return shortcut.isValid ? shortcut : nil
    }
}

@MainActor final class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()
    @Published private(set) var shortcut: CaptureShortcut
    @Published private(set) var isRegistered = false
    @Published private(set) var error: String?
    @Published var isRecording = false
    private let defaults: UserDefaults
    private var register: ((CaptureShortcut) -> OSStatus)?
    private var didChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "captureShortcut"),
           let saved = try? JSONDecoder().decode(CaptureShortcut.self, from: data), saved.isValid {
            shortcut = saved
        } else { shortcut = .standard }
    }

    func connect(register: @escaping (CaptureShortcut) -> OSStatus, didChange: @escaping () -> Void = {}) {
        self.register = register
        self.didChange = didChange
        let status = register(shortcut)
        isRegistered = status == noErr
        error = status == noErr ? nil : "This shortcut is unavailable. Choose another combination."
        didChange()
    }

    @discardableResult func set(_ candidate: CaptureShortcut) -> Bool {
        guard candidate.isValid else { error = "Use Control, Option, or Command with another key."; return false }
        guard let register else { error = "The shortcut service is unavailable."; return false }
        if candidate == shortcut && isRegistered { error = nil; return true }
        let status = register(candidate)
        guard status == noErr else {
            error = status == eventHotKeyExistsErr ? "That shortcut is already in use. Try another combination." : "macOS couldn’t register that shortcut. Try another combination."
            return false
        }
        shortcut = candidate
        isRegistered = true
        error = nil
        defaults.set(try? JSONEncoder().encode(candidate), forKey: "captureShortcut")
        didChange?()
        return true
    }
}
