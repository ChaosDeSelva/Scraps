import SwiftUI
import AppKit

enum Palette {
    static let canvas = Color(hex: 0xF3F1E9)
    static let sidebar = Color(hex: 0xEAE8DD)
    static let paper = Color(hex: 0xFFFEFA)
    static let ink = Color(hex: 0x25271E)
    static let body = Color(hex: 0x4D5045)
    static let muted = Color(hex: 0x727466)
    static let line = Color(hex: 0xD9DACD)
    static let yellow = Color(hex: 0xF7A501)
    static let selected = Color(hex: 0xF6E4B5)
    static let green = Color(hex: 0x397052)
    static let code = Color(hex: 0x292D25)
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
            .foregroundStyle(Palette.ink)
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
            .foregroundStyle(Palette.ink).frame(width: size, height: size)
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
