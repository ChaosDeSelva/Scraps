import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var shortcuts = ShortcutSettings.shared
    @State private var eventMonitor: Any?
    @State private var recordingError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings").font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance").font(.system(size: 13, weight: .semibold))
                Picker("Appearance", selection: $appearance.choice) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Quick capture shortcut").font(.system(size: 13, weight: .semibold))
                HStack {
                    Button(action: startRecording) {
                        Label(shortcuts.isRecording ? "Press a shortcut…" : shortcuts.shortcut.displayName, systemImage: "keyboard")
                            .frame(minWidth: 160)
                    }.buttonStyle(PaperButton(primary: shortcuts.isRecording))
                        .accessibilityLabel("Record quick capture shortcut")
                        .accessibilityValue(shortcuts.isRecording ? "Recording" : shortcuts.shortcut.displayName)
                    if shortcuts.isRecording {
                        Button("Cancel", action: stopRecording).buttonStyle(PaperButton())
                    } else {
                        Button("Reset to default") { shortcuts.set(.standard) }
                            .buttonStyle(PaperButton()).disabled(shortcuts.shortcut == .standard && shortcuts.isRegistered)
                    }
                }
                Text(shortcuts.isRecording ? "Use Control, Option, or Command with another key. Escape cancels." : "Click the shortcut to change it. Works from any app.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let error = recordingError ?? (shortcuts.isRecording ? nil : shortcuts.error) {
                    Text(error).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Text("Changes are saved on this Mac.").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
        .padding(28).frame(width: 480, height: 350).background(Palette.canvas).foregroundStyle(Palette.ink)
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if (notification.object as? NSWindow)?.identifier?.rawValue == "ScrapsSettings" { stopRecording() }
        }
        .onReceive(shortcuts.$isRecording) { recording in
            if !recording { recordingError = nil; removeMonitor() }
        }
    }

    private func startRecording() {
        removeMonitor()
        recordingError = nil
        shortcuts.isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window?.identifier?.rawValue == "ScrapsSettings" else { return event }
            if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return nil }
            if event.isARepeat { return nil }
            guard let candidate = CaptureShortcut.recorded(from: event) else {
                recordingError = "Use Control, Option, or Command with another key."
                return nil
            }
            stopRecording()
            shortcuts.set(candidate)
            return nil
        }
    }

    private func stopRecording() {
        shortcuts.isRecording = false
        recordingError = nil
        removeMonitor()
    }

    private func removeMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}
