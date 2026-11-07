// Removes the leftover magenta key-colour fringe around the pop-outs (plant, record player, scarf, cat) in place.
// Usage, from the repo root: swift scripts/clean-fringe.swift art/scene_*.png
// Only the outer band of the picture is touched, where nothing in the room is magenta (the pink desk clock is far inside).
import AppKit

for path in CommandLine.arguments.dropFirst() {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("cannot read \(path)"); continue }
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var erased = 0, tinted = 0
    for y in 0..<h {
        for x in 0..<w {
            guard x < 330 || x > w - 330 || y < 120 || y > h - 120 else { continue }
            let i = (y * w + x) * 4
            let a = Double(buf[i + 3]) / 255
            guard a > 0 else { continue }
            var r = Double(buf[i]) / 255 / a, g = Double(buf[i + 1]) / 255 / a, b = Double(buf[i + 2]) / 255 / a
            let m = min(r, b) - g
            guard m > 0.03, abs(r - b) < 0.3, r > 0.15 else { continue }
            if m > 0.28 {
                buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
                erased += 1
            } else {
                r -= m; b -= m; g = max(0, min(1, g))
                buf[i] = UInt8(max(0, min(255, r * a * 255))); buf[i + 1] = UInt8(g * a * 255); buf[i + 2] = UInt8(max(0, min(255, b * a * 255)))
                tinted += 1
            }
        }
    }
    let out = ctx.makeImage()!
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        FileHandle.standardError.write("\(path): cannot write\n".data(using: .utf8)!); exit(1)
    }
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("\(path): saving failed\n".data(using: .utf8)!); exit(1)
    }
    print("\(path): erased \(erased), tinted \(tinted)")
}
