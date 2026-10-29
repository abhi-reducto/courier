// Renders Drop's app icon to a 1024px PNG: swift make-icon.swift out.png
// install.sh turns it into AppIcon.icns.
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: 824pt rounded square centered on the 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.66, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.36, blue: 0.95, alpha: 1)])!
        .draw(in: body, angle: -90)
    // Soft highlight across the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // White tray glyph with a gentle drop shadow.
    let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
    if let glyph = NSImage(systemSymbolName: "tray.and.arrow.down.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { r in
            glyph.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let g = tinted.size
        let rect = NSRect(x: (size - g.width) / 2, y: (size - g.height) / 2 - 10, width: g.width, height: g.height)
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor(srgbRed: 0.08, green: 0.15, blue: 0.5, alpha: 0.35)
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.shadowBlurRadius = 24
        s.set()
        tinted.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
