// Renders Courier's app icon (a parcel in motion) to a 1024px PNG: swift make-icon.swift out.png
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
    // Warm amber to tangerine.
    NSGradient(colors: [NSColor(srgbRed: 1.0, green: 0.72, blue: 0.30, alpha: 1),
                        NSColor(srgbRed: 0.94, green: 0.42, blue: 0.15, alpha: 1)])!
        .draw(in: body, angle: -90)
    // Soft highlight across the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Speed lines trailing the parcel.
    NSColor.white.withAlphaComponent(0.55).setStroke()
    for (y, length) in [(580.0, 150.0), (490.0, 210.0), (400.0, 130.0)] {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 170, y: y))
        line.line(to: NSPoint(x: 170 + length, y: y))
        line.lineWidth = 26
        line.lineCapStyle = .round
        line.stroke()
    }

    // White parcel with a gentle drop shadow, nudged right to make room for the lines.
    let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
    if let glyph = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: glyph.size, flipped: false) { r in
            glyph.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let g = tinted.size
        let rect = NSRect(x: (size - g.width) / 2 + 70, y: (size - g.height) / 2 - 10, width: g.width, height: g.height)
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor(srgbRed: 0.59, green: 0.2, blue: 0.0, alpha: 0.35)
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
