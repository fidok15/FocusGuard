import AppKit

/// Kitchen-timer glyph for the menu bar, as a template image so it follows the light/dark menu bar.
/// Idle: empty dial. Studying: a focus wedge. Alert: wedge plus "!".
enum MenuIcon {
    enum Mood { case idle, studying, alert }

    /// The label refreshes every second; draw each mood once.
    static func image(_ mood: Mood) -> NSImage {
        if let cached = cache[mood] { return cached }
        let image = draw(mood)
        cache[mood] = image
        return image
    }

    private static var cache: [Mood: NSImage] = [:]

    private static func draw(_ mood: Mood) -> NSImage {
        let width: CGFloat = mood == .alert ? 23 : 18
        let image = NSImage(size: NSSize(width: width, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Timer body with a knob on top.
            let body = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1, width: 15, height: 14), xRadius: 4, yRadius: 4)
            body.lineWidth = 1.6
            body.stroke()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 15, width: 4, height: 2.2), xRadius: 1, yRadius: 1).fill()

            // Dial.
            let center = CGPoint(x: 9, y: 8)
            let dial = NSBezierPath(ovalIn: NSRect(x: center.x - 4.6, y: center.y - 4.6, width: 9.2, height: 9.2))
            dial.lineWidth = 1.1
            dial.stroke()

            if mood == .idle {
                let hand = NSBezierPath()
                hand.move(to: center)
                hand.line(to: CGPoint(x: center.x + 2.9, y: center.y + 1.7)) // pointing at 2 o'clock, unlike a power glyph
                hand.move(to: CGPoint(x: center.x, y: center.y + 3.6))
                hand.line(to: CGPoint(x: center.x, y: center.y + 2.6)) // 12 o'clock tick
                hand.lineWidth = 1.3
                hand.lineCapStyle = .round
                hand.stroke()
            } else {
                // Focus wedge: from 12 o'clock, clockwise, two thirds of the dial.
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: 3.6, startAngle: 90, endAngle: -150, clockwise: true)
                wedge.close()
                wedge.fill()
            }

            if mood == .alert {
                NSBezierPath(roundedRect: NSRect(x: 19.6, y: 6.4, width: 2.2, height: 9.6), xRadius: 1.1, yRadius: 1.1).fill()
                NSBezierPath(ovalIn: NSRect(x: 19.5, y: 1.8, width: 2.4, height: 2.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
