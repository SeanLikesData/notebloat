import AppKit

/// A custom template menu bar icon for Notebloat.
///
/// The shape is a small bloated note: a rounded note body, a folded corner,
/// three writing lines, and a small filled dot. It reads more like a branded
/// scratchpad than the generic SF Symbols note icon, while still behaving like
/// a normal monochrome macOS menu bar item.
enum StatusIcon {
    static var notebloat: NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let body = NSBezierPath(roundedRect: NSRect(x: 3.0, y: 2.5, width: 12.0, height: 13.0), xRadius: 3.0, yRadius: 3.0)
        body.lineWidth = 1.7
        body.stroke()

        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 11.0, y: 15.5))
        fold.line(to: NSPoint(x: 15.0, y: 11.5))
        fold.line(to: NSPoint(x: 11.0, y: 11.5))
        fold.close()
        fold.lineWidth = 1.25
        fold.stroke()

        drawLine(from: NSPoint(x: 6.0, y: 11.2), to: NSPoint(x: 10.0, y: 11.2))
        drawLine(from: NSPoint(x: 6.0, y: 8.6), to: NSPoint(x: 12.0, y: 8.6))
        drawLine(from: NSPoint(x: 6.0, y: 6.0), to: NSPoint(x: 10.4, y: 6.0))

        let dot = NSBezierPath(ovalIn: NSRect(x: 11.5, y: 4.4, width: 3.0, height: 3.0))
        dot.fill()

        image.isTemplate = true
        image.accessibilityDescription = "Notebloat"
        return image
    }

    private static func drawLine(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineCapStyle = .round
        path.lineWidth = 1.35
        path.stroke()
    }
}
