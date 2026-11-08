import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let s = size

        let inset = s * 0.1
        let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = s * 0.025
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
        shadow.set()
        NSColor(srgbRed: 0.16, green: 0.47, blue: 0.84, alpha: 1).setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.62, blue: 0.98, alpha: 1),
                            NSColor(srgbRed: 0.10, green: 0.33, blue: 0.75, alpha: 1)])?
            .draw(in: tilePath, angle: -90)

        let bubble = NSRect(x: tile.minX + tile.width * 0.17, y: tile.minY + tile.height * 0.27,
                            width: tile.width * 0.66, height: tile.height * 0.52)
        let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: bubble.height * 0.3, yRadius: bubble.height * 0.3)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubble.minX + bubble.width * 0.22, y: bubble.minY + 1))
        tail.line(to: NSPoint(x: bubble.minX + bubble.width * 0.12, y: bubble.minY - bubble.height * 0.26))
        tail.line(to: NSPoint(x: bubble.minX + bubble.width * 0.42, y: bubble.minY + 1))
        tail.close()
        bubblePath.append(tail)
        NSGraphicsContext.saveGraphicsState()
        let soft = NSShadow()
        soft.shadowColor = NSColor.black.withAlphaComponent(0.18)
        soft.shadowBlurRadius = s * 0.02
        soft.shadowOffset = NSSize(width: 0, height: -s * 0.008)
        soft.set()
        NSColor.white.setFill()
        bubblePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let config = NSImage.SymbolConfiguration(pointSize: bubble.height * 0.62, weight: .heavy)
            .applying(.init(paletteColors: [NSColor(srgbRed: 0.13, green: 0.42, blue: 0.85, alpha: 1)]))
        if let mark = NSImage(systemSymbolName: "questionmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let m = mark.size
            mark.draw(in: NSRect(x: bubble.midX - m.width / 2, y: bubble.midY - m.height / 2, width: m.width, height: m.height))
        }
        return true
    }
}

func png(_ image: NSImage, pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! png(drawIcon(size: CGFloat(pixels)), pixels: pixels).write(to: iconset.appendingPathComponent(name))
    }
}
try! fm.createDirectory(atPath: "Risorse", withIntermediateDirectories: true)
try! fm.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try! png(drawIcon(size: 1024), pixels: 1024).write(to: URL(fileURLWithPath: "docs/icona.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "Risorse/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Creati Risorse/AppIcon.icns e docs/icona.png" : "iconutil non riuscito")
