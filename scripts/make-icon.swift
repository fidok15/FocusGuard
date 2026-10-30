// Renders Resources/AppIcon.icns from the morning scene: the study timer (with a focus wedge) and notebook.
// Usage, from the repo root: swift scripts/make-icon.swift   (needs iconutil, part of the Command Line Tools)
import AppKit

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "art/scene_morning.jpeg") as CFURL, nil)!
let art = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let pw = CGFloat(art.width), ph = CGFloat(art.height)

// Square around the kitchen timer and the open notebook (measured on the 2000×1116 preview of the art).
let side = 0.165 * pw
let center = CGPoint(x: 475.0 / 2000 * pw, y: 750.0 / 1116 * ph)
let cropRect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
let plain = art.cropping(to: cropRect)!

// Paint the red focus wedge on the timer's blank dial, like the app does while you study.
let crop: CGImage = {
    let w = plain.width, h = plain.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(plain, in: CGRect(x: 0, y: 0, width: w, height: h))
    let dial = CGPoint(x: 470.0 / 2000 * pw - cropRect.minX, y: 735.0 / 1116 * ph - cropRect.minY)
    let c = CGPoint(x: dial.x, y: CGFloat(h) - dial.y) // CG origin is bottom-left
    let r = 52.0 / 2000 * pw * 0.82
    ctx.move(to: c)
    ctx.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * 0.7, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(red: 0.86, green: 0.3, blue: 0.27, alpha: 0.85)
    ctx.fillPath()
    let end = CGFloat.pi / 2 - 2 * .pi * 0.7
    ctx.move(to: c)
    ctx.addLine(to: CGPoint(x: c.x + cos(end) * r, y: c.y + sin(end) * r))
    ctx.setStrokeColor(red: 0.24, green: 0.2, blue: 0.18, alpha: 1)
    ctx.setLineWidth(r * 0.08)
    ctx.strokePath()
    return ctx.makeImage()!
}()

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with a soft drop shadow.
    let body = CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = CGPath(roundedRect: body, cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 10 / 1024), blur: s * 22 / 1024,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(crop, in: body)
    ctx.restoreGState()

    // Thin inner outline so the edge doesn't blur into light backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(max(1, s * 2 / 1024))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
