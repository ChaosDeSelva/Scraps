import AppKit
import SwiftUI

@main struct AppearanceTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "scraps-appearance-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppearanceSettings(defaults: defaults)
        precondition(settings.choice == .system, "New installations must follow macOS")
        settings.choice = .dark
        precondition(NSApp.appearance?.name == .darkAqua, "Dark must update native windows")
        precondition(AppearanceSettings(defaults: defaults).choice == .dark, "Appearance must survive relaunch")
        settings.choice = .light
        precondition(NSApp.appearance?.name == .aqua, "Light must override a dark system")
        settings.choice = .system
        precondition(NSApp.appearance == nil, "System must remove the override so OS changes propagate")
        defaults.set("unsupported", forKey: "appearance")
        precondition(AppearanceSettings(defaults: defaults).choice == .system, "Unknown settings must safely follow macOS")

        var canvasLuminance: [Double] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                canvasLuminance.append(luminance(Palette.canvas))
                for surface in [Palette.canvas, Palette.sidebar, Palette.paper] {
                    precondition(contrast(Palette.ink, surface) >= 4.5, "Main text must be readable")
                    precondition(contrast(Palette.body, surface) >= 4.5, "Body text must be readable")
                    precondition(contrast(Palette.muted, surface) >= 4.5, "Metadata must be readable")
                }
                precondition(contrast(Palette.onAccent, Palette.yellow) >= 4.5, "Yellow buttons need dark text in both modes")
                precondition(contrast(Palette.ink, Palette.selected) >= 4.5, "Selected options must be readable")
            }
        }
        precondition(canvasLuminance[1] < canvasLuminance[0] / 4, "Dynamic surfaces must resolve to a dark palette")
        print("Appearance tests passed: persistence, native overrides, system following and text contrast.")
    }

    static func contrast(_ foreground: Color, _ background: Color) -> Double {
        let a = luminance(foreground), b = luminance(background)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func luminance(_ color: Color) -> Double {
        let resolved = NSColor(color).usingColorSpace(.sRGB)!
        let channels = [resolved.redComponent, resolved.greenComponent, resolved.blueComponent].map { value -> Double in
            let v = Double(value)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
