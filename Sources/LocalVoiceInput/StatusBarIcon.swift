import AppKit

@MainActor
final class StatusBarIcon {
    func image() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setFill()

        let canopy = NSBezierPath()
        canopy.move(to: NSPoint(x: 9.0, y: 16.2))
        canopy.curve(
            to: NSPoint(x: 2.3, y: 7.7),
            controlPoint1: NSPoint(x: 4.8, y: 16.0),
            controlPoint2: NSPoint(x: 1.9, y: 12.5)
        )
        canopy.curve(
            to: NSPoint(x: 7.6, y: 6.8),
            controlPoint1: NSPoint(x: 3.3, y: 6.6),
            controlPoint2: NSPoint(x: 5.5, y: 6.3)
        )
        canopy.line(to: NSPoint(x: 7.6, y: 5.4))
        canopy.curve(
            to: NSPoint(x: 5.2, y: 3.5),
            controlPoint1: NSPoint(x: 6.9, y: 4.7),
            controlPoint2: NSPoint(x: 6.1, y: 4.1)
        )
        canopy.curve(
            to: NSPoint(x: 7.8, y: 3.7),
            controlPoint1: NSPoint(x: 6.3, y: 3.5),
            controlPoint2: NSPoint(x: 7.1, y: 3.6)
        )
        canopy.line(to: NSPoint(x: 7.8, y: 1.8))
        canopy.line(to: NSPoint(x: 10.2, y: 1.8))
        canopy.line(to: NSPoint(x: 10.2, y: 3.7))
        canopy.curve(
            to: NSPoint(x: 12.8, y: 3.5),
            controlPoint1: NSPoint(x: 10.9, y: 3.6),
            controlPoint2: NSPoint(x: 11.7, y: 3.5)
        )
        canopy.curve(
            to: NSPoint(x: 10.4, y: 5.4),
            controlPoint1: NSPoint(x: 11.9, y: 4.1),
            controlPoint2: NSPoint(x: 11.1, y: 4.7)
        )
        canopy.line(to: NSPoint(x: 10.4, y: 6.8))
        canopy.curve(
            to: NSPoint(x: 15.7, y: 7.7),
            controlPoint1: NSPoint(x: 12.5, y: 6.3),
            controlPoint2: NSPoint(x: 14.7, y: 6.6)
        )
        canopy.curve(
            to: NSPoint(x: 9.0, y: 16.2),
            controlPoint1: NSPoint(x: 16.1, y: 12.5),
            controlPoint2: NSPoint(x: 13.2, y: 16.0)
        )
        canopy.close()
        canopy.fill()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
