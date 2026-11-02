// Turns the flat border colour around each generated scene into transparency.
// Usage, from the repo root: swift scripts/key-art.swift <in.jpeg> <out.png>
// The key colour is sampled from the corners (Gemini doesn't always hit exact #FF00FF). Only pixels
// connected to the image edge are keyed (flood fill), so dim purple walls inside the room stay opaque.
import AppKit

let input = CommandLine.arguments[1], output = CommandLine.arguments[2]
let original = NSImage(contentsOfFile: input)!
let w = 2000 // plenty for a 720 pt window on Retina
let h = 1116 // fixed: the app measures art on a 2000x1116 grid; Gemini outputs vary by a pixel or two

// Draw into a known RGBA8 buffer at the output size.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: w * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
original.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()
let px = rep.bitmapData!

func color(_ i: Int) -> (Double, Double, Double) {
    (Double(px[i * 4]) / 255, Double(px[i * 4 + 1]) / 255, Double(px[i * 4 + 2]) / 255)
}
func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
// Top and bottom borders are sampled separately: the generator sometimes shades the bottom border darker
// (morning: 0.70 vs 0.94), and a single key left an opaque magenta band there.
func sampleKey(_ pts: [(Int, Int)]) -> (Double, Double, Double) {
    let c = pts.map { color($0.1 * w + $0.0) }
    return (median(c.map(\.0)), median(c.map(\.1)), median(c.map(\.2)))
}
let key = sampleKey([(4, 4), (w - 5, 4), (w / 2, 3)])
let keyBottom = sampleKey([(4, h - 5), (w - 5, h - 5), (w / 2, h - 4)])
func distance(_ i: Int) -> Double {
    let c = color(i)
    return [key, keyBottom].map { sqrt(pow(c.0 - $0.0, 2) + pow(c.1 - $0.1, 2) + pow(c.2 - $0.2, 2)) }.min()!
}

// ponytail: tolerances tuned on the four Gemini scenes. A vivid magenta border is far from any room
// colour and can be keyed loosely; a muted purple one sits close to shadows, so it gets tight limits.
let vivid = max(key.0, key.1, key.2) - min(key.0, key.1, key.2) > 0.5
let inner = vivid ? 0.18 : 0.07, outer = vivid ? 0.34 : 0.14, pocket = vivid ? 0.12 : 0.05

// Flood fill from every edge pixel through key-coloured pixels.
var keyed = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
// Pockets trapped between leaves or scarf fringe near the edge: seed them too, but only in the
// outer band and only when they are almost exactly the key colour (the room inside stays safe).
let band = 0.08
for i in 0..<(w * h) {
    let x = Double(i % w) / Double(w), y = Double(i / w) / Double(h)
    if (x < band || x > 1 - band || y < band || y > 1 - band) && distance(i) < pocket { stack.append(i) }
}
while let i = stack.popLast() {
    if keyed[i] || distance(i) > outer { continue }
    keyed[i] = true
    let x = i % w, y = i / w
    if x > 0 { stack.append(i - 1) }
    if x < w - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - w) }
    if y < h - 1 { stack.append(i + w) }
}

// Alpha from distance inside the keyed region; despill a 2 px ring around it.
for i in 0..<(w * h) {
    var (r, g, b) = color(i)
    var alpha = 1.0
    if keyed[i] { alpha = max(0, min(1, (distance(i) - inner) / (outer - inner))) }
    let x = i % w, y = i / w
    let nearKey = keyed[i] || (x > 1 && keyed[i - 2]) || (x < w - 2 && keyed[i + 2])
        || (y > 1 && keyed[i - 2 * w]) || (y < h - 2 && keyed[i + 2 * w])
    if nearKey {
        let spill = max(0, min(r, b) - g) * (keyed[i] ? 1 : 0.6)
        r -= spill; b -= spill
    }
    px[i * 4] = UInt8(max(0, min(255, r * alpha * 255)))     // premultiplied
    px[i * 4 + 1] = UInt8(max(0, min(255, g * alpha * 255)))
    px[i * 4 + 2] = UInt8(max(0, min(255, b * alpha * 255)))
    px[i * 4 + 3] = UInt8(alpha * 255)
}
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output) \(w)x\(h)", String(format: "key r%.2f g%.2f b%.2f", key.0, key.1, key.2))
