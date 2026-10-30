import AppKit

/// Hand-drawn cat head for the menu bar, as a template image so it follows the light/dark menu bar.
enum MenuIcon {
    enum Mood { case sleeping, studying, alert }

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

            // Filled separately so opposite winding never punches holes where ears meet the head.
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 12)).fill()
            ear([CGPoint(x: 2.6, y: 8.5), CGPoint(x: 3.8, y: 16.6), CGPoint(x: 8.2, y: 12.6)]).fill()
            ear([CGPoint(x: 9.8, y: 12.6), CGPoint(x: 14.2, y: 16.6), CGPoint(x: 15.4, y: 8.5)]).fill()

            // Eyes and nose are cut out of the silhouette.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            switch mood {
            case .sleeping:
                for x in [5.6, 12.4] {
                    let lid = NSBezierPath()
                    lid.appendArc(withCenter: CGPoint(x: x, y: 8.4), radius: 1.7, startAngle: 200, endAngle: 340)
                    lid.lineWidth = 1.3
                    lid.lineCapStyle = .round
                    lid.stroke()
                }
            case .studying, .alert:
                for x in [5.6, 12.4] {
                    NSBezierPath(ovalIn: NSRect(x: x - 1.2, y: 6.4, width: 2.4, height: 3.2)).fill()
                }
            }
            let nose = NSBezierPath()
            nose.move(to: CGPoint(x: 8.1, y: 5.6))
            nose.line(to: CGPoint(x: 9.9, y: 5.6))
            nose.line(to: CGPoint(x: 9, y: 4.5))
            nose.close()
            nose.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            if mood == .alert {
                NSBezierPath(roundedRect: NSRect(x: 19.6, y: 6.4, width: 2.2, height: 9.6), xRadius: 1.1, yRadius: 1.1).fill()
                NSBezierPath(ovalIn: NSRect(x: 19.5, y: 1.8, width: 2.4, height: 2.4)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func ear(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.line(to: $0) }
        path.close()
        path.lineJoinStyle = .round
        return path
    }
}
