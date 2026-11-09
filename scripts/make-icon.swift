// Renders Resources/AppIcon.icns from the day scene: the desk clock with 25:00 drawn on its LCD (study theme, no cat).
// Usage, from the repo root: swift scripts/make-icon.swift   (needs iconutil, part of the Command Line Tools)
import AppKit

let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: "art/scene_day.png") as CFURL, nil)!
let art = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let pw = CGFloat(art.width), ph = CGFloat(art.height)

// Square around the clock (measured on the 2000x1116 art; the PNG is that size).
let side: CGFloat = 290
let center = CGPoint(x: 609, y: 712)
let cropRect = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
let plain = art.cropping(to: cropRect)!

// Seven-segment digits on the clock's sheared glass, same geometry as the app (DeskScene.swift).
let glass = [CGPoint(x: 548, y: 704), CGPoint(x: 711, y: 683), CGPoint(x: 711, y: 727), CGPoint(x: 549, y: 752)]
let masks: [UInt8] = [0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110, 0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111]
let crop: CGImage = {
    let w = plain.width, h = plain.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(plain, in: CGRect(x: 0, y: 0, width: w, height: h))
    // Glass-local (0...207, 0...66) to crop pixels (CG origin is bottom-left).
    func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let u = x / 207, v = y / 66
        let ax = (1 - u) * (1 - v) * glass[0].x + u * (1 - v) * glass[1].x + u * v * glass[2].x + (1 - u) * v * glass[3].x
        let ay = (1 - u) * (1 - v) * glass[0].y + u * (1 - v) * glass[1].y + u * v * glass[2].y + (1 - u) * v * glass[3].y
        return CGPoint(x: ax - cropRect.minX, y: CGFloat(h) - (ay - cropRect.minY))
    }
    let dw: CGFloat = 36, dh: CGFloat = 50, t: CGFloat = 7, slant: CGFloat = 0.12
    func poly(_ pts: [CGPoint], _ dx: CGFloat, _ dy: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for (i, pt) in pts.enumerated() {
            let q = map(pt.x + dx + slant * (dh / 2 - pt.y), pt.y + dy)
            i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        p.closeSubpath()
        return p
    }
    func segment(_ i: Int, _ x0: CGFloat, _ y0: CGFloat) -> CGPath {
        func hz(_ yc: CGFloat) -> [CGPoint] {
            [CGPoint(x: t * 0.55, y: yc), CGPoint(x: t * 1.1, y: yc - t / 2), CGPoint(x: dw - t * 1.1, y: yc - t / 2),
             CGPoint(x: dw - t * 0.55, y: yc), CGPoint(x: dw - t * 1.1, y: yc + t / 2), CGPoint(x: t * 1.1, y: yc + t / 2)]
        }
        func vt(_ xc: CGFloat, _ top: CGFloat, _ bottom: CGFloat) -> [CGPoint] {
            [CGPoint(x: xc, y: top + t * 0.55), CGPoint(x: xc + t / 2, y: top + t * 1.05), CGPoint(x: xc + t / 2, y: bottom - t * 1.05),
             CGPoint(x: xc, y: bottom - t * 0.55), CGPoint(x: xc - t / 2, y: bottom - t * 1.05), CGPoint(x: xc - t / 2, y: top + t * 1.05)]
        }
        let pts: [CGPoint]
        switch i {
        case 0: pts = hz(t / 2)
        case 1: pts = vt(dw - t / 2, 0, dh / 2 + t * 0.3)
        case 2: pts = vt(dw - t / 2, dh / 2 - t * 0.3, dh)
        case 3: pts = hz(dh - t / 2)
        case 4: pts = vt(t / 2, dh / 2 - t * 0.3, dh)
        case 5: pts = vt(t / 2, 0, dh / 2 + t * 0.3)
        default: pts = hz(dh / 2)
        }
        return poly(pts, x0, y0)
    }
    let total: CGFloat = 4 * dw + 2 * 6 + 22
    let left = (207 - total) / 2 - 2, top: CGFloat = (66 - dh) / 2 + 1
    let xs = [left, left + dw + 6, left + 2 * dw + 6 + 22, left + 3 * dw + 12 + 22]
    func drawDigits(_ color: CGColor) {
        ctx.setFillColor(color)
        for (i, d) in [2, 5, 0, 0].enumerated() {
            for s in 0..<7 where masks[d] & (1 << UInt8(s)) != 0 { ctx.addPath(segment(s, xs[i], top)); ctx.fillPath() }
        }
        let cx = left + 2 * dw + 6 + 11
        for cy in [top + dh * 0.32, top + dh * 0.68] {
            let p = CGMutablePath()
            for (i, c) in [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)].enumerated() {
                let q = map(cx + c.x * t * 0.45 + slant * (dh / 2 - (cy - top)), cy + c.y * t * 0.45)
                i == 0 ? p.move(to: q) : p.addLine(to: q)
            }
            p.closeSubpath(); ctx.addPath(p); ctx.fillPath()
        }
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 14, color: CGColor(red: 0.4, green: 1, blue: 0.55, alpha: 0.9))
    drawDigits(CGColor(red: 0.55, green: 0.95, blue: 0.62, alpha: 1))
    ctx.restoreGState()
    drawDigits(CGColor(red: 0.7, green: 1, blue: 0.75, alpha: 1))
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
