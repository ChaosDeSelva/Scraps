import AppKit
import Carbon

@main struct ShortcutTests {
    @MainActor static func main() {
        let suite = "scraps-shortcut-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ShortcutSettings(defaults: defaults)
        precondition(settings.shortcut == .standard, "First launch must keep the familiar default")
        var registrationResult: OSStatus = noErr
        var registrations: [CaptureShortcut] = []
        settings.connect(register: { candidate in registrations.append(candidate); return registrationResult })
        precondition(settings.isRegistered)

        let custom = CaptureShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey), key: "S")
        precondition(settings.set(custom))
        precondition(custom.displayName == "⇧⌘S")
        precondition(ShortcutSettings(defaults: defaults).shortcut == custom, "Custom keys must survive relaunch")
        let saved = defaults.data(forKey: "captureShortcut")

        registrationResult = OSStatus(eventHotKeyExistsErr)
        precondition(!settings.set(.standard), "A conflicting shortcut must fail")
        precondition(settings.shortcut == custom && settings.isRegistered, "Failure must retain the previous working shortcut")
        precondition(defaults.data(forKey: "captureShortcut") == saved, "Failed registration must not overwrite the saved preference")
        precondition(settings.error?.contains("already in use") == true)

        let count = registrations.count
        precondition(!settings.set(CaptureShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(shiftKey), key: "S")))
        precondition(registrations.count == count, "Invalid combinations must never reach native registration")
        registrationResult = noErr
        precondition(settings.set(.standard))
        precondition(settings.error == nil && ShortcutSettings(defaults: defaults).shortcut == .standard, "Reset must persist and clear errors")

        defaults.set(Data("invalid".utf8), forKey: "captureShortcut")
        precondition(ShortcutSettings(defaults: defaults).shortcut == .standard, "Corrupt preferences must use the default")
        let unavailable = ShortcutSettings(defaults: defaults)
        unavailable.connect(register: { _ in OSStatus(eventHotKeyExistsErr) })
        precondition(!unavailable.isRegistered && unavailable.error != nil, "Startup conflicts must be visible")

        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0,
                                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: UInt16(kVK_LeftArrow))!
        precondition(CaptureShortcut.recorded(from: arrow)?.displayName == "⌃⌥←", "Special keys need readable labels")
        print("Shortcut tests passed: recording, persistence, validation, reset and conflict recovery.")
    }
}
