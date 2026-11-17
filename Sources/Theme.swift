import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Follow macOS"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    private let defaults: UserDefaults
    @Published var choice: AppAppearance {
        didSet {
            defaults.set(choice.rawValue, forKey: "appearance")
            apply()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        choice = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    }

    func apply() { NSApp.appearance = choice.nativeAppearance }
}

enum Palette {
    static let canvas = adaptive(light: 0xF3F1E9, dark: 0x1C201A)
    static let sidebar = adaptive(light: 0xEAE8DD, dark: 0x171B16)
    static let paper = adaptive(light: 0xFFFEFA, dark: 0x252A22)
    static let ink = adaptive(light: 0x25271E, dark: 0xF2F1E8)
    static let body = adaptive(light: 0x4D5045, dark: 0xCBD0C0)
    static let muted = adaptive(light: 0x65695B, dark: 0xA0AA97)
    static let line = adaptive(light: 0xD9DACD, dark: 0x444D3D)
    static let yellow = Color(hex: 0xF7A501)
    static let onAccent = Color(hex: 0x25271E)
    static let selected = adaptive(light: 0xF6E4B5, dark: 0x51411F)
    static let green = adaptive(light: 0x397052, dark: 0x7BC89C)
    static let code = adaptive(light: 0x292D25, dark: 0x171B15)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct PaperButton: ButtonStyle {
    var primary = false
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .semibold))
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 7 : 10)
            .background(primary ? Palette.yellow : Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Palette.ink.opacity(0.16) : Palette.line, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.42)
            .contentShape(Rectangle())
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14))
                .foregroundStyle(active ? Palette.ink : Palette.body)
                .frame(width: 32, height: 32)
                .background(active ? Palette.selected : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.4).foregroundStyle(Palette.muted)
    }
}

struct BrandMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "paperclip").font(.system(size: size * 0.53, weight: .semibold))
            .foregroundStyle(Palette.onAccent).frame(width: size, height: size)
            .background(Palette.yellow).clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.ink.opacity(0.16), lineWidth: 1))
            .rotationEffect(.degrees(-6)).accessibilityHidden(true)
    }
}

struct TagChip: View {
    let text: String
    var body: some View {
        Text("# " + text).font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.body).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Palette.canvas).clipShape(RoundedRectangle(cornerRadius: 4))
            .help(text)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, point) in layout.positions.enumerated() {
            let measured = subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                 proposal: ProposedViewSize(width: min(measured.width, bounds.width), height: measured.height))
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let width = proposal.width ?? 500
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if x > 0 && x + itemWidth > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

struct PaperField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.body)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain).font(.system(size: 14))
                .padding(10).background(Palette.paper)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
                .accessibilityLabel(title)
        }
    }
}

struct ContentEditor: View {
    @Binding var text: String
    var code = false
    var minimum: CGFloat = 150
    var label = "Content"

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14, design: code ? .monospaced : .default))
            .foregroundStyle(Palette.ink).scrollContentBackground(.hidden)
            .padding(9).frame(minHeight: minimum)
            .background(Palette.paper).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
            .accessibilityLabel(label)
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
