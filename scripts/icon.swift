import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = CGFloat(size) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
    NSColor(srgbRed: 0.97, green: 0.65, blue: 0.004, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.19, yRadius: CGFloat(size) * 0.19).fill()
    if let symbol = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: CGFloat(size) * 0.51, weight: .semibold)) {
        let symbolRect = NSRect(x: CGFloat(size) * 0.27, y: CGFloat(size) * 0.23, width: CGFloat(size) * 0.46, height: CGFloat(size) * 0.54)
        symbol.draw(in: symbolRect)
    }
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    let filename: String
    if size == 1024 { filename = "icon_512x512@2x.png" }
    else { filename = "icon_\(size)x\(size).png" }
    if size != 64 { try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename)) }
    if [32, 64, 256, 512].contains(size) {
        let half = size / 2
        try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(half)x\(half)@2x.png"))
    }
}
