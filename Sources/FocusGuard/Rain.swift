import AVFoundation
import SwiftUI

/// Rain falling outside the window of the rainy scene, behind the cat. The art already has painted rain; this only moves it.
struct RainFall: View {
    /// The window opening in art coordinates (between the open casements, from under the lights down to the sill).
    private static let opening = CGRect(origin: P(824, 150), size: CGSize(width: P(1296, 0).x - P(824, 0).x, height: P(0, 556).y - P(0, 150).y))

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, _ in
                let t = context.date.timeIntervalSinceReferenceDate
                let r = Self.opening
                ctx.clip(to: Path(r))
                for i in 0..<110 {
                    let near = i % 3 == 0
                    let len: CGFloat = near ? 11 : 7
                    let speed = (near ? 260 : 180) * (1 + 0.15 * wob(Double(i), 2))
                    let span = r.height + len
                    let fall = (CGFloat(t) * speed + (wob(Double(i), 3) + 1) * span * 3).truncatingRemainder(dividingBy: span)
                    let y = r.minY - len + fall
                    let x = r.minX - 10 + (wob(Double(i), 1) + 1) / 2 * (r.width + 30) - fall * 0.1 // a little wind
                    let fade = min(1, max(0, (y - r.minY) / 40)) // thin out under the string lights
                    var drop = Path()
                    drop.move(to: CGPoint(x: x, y: y))
                    drop.addLine(to: CGPoint(x: x - len * 0.1, y: y + len))
                    ctx.stroke(drop, with: .color(.white.opacity((near ? 0.45 : 0.28) * fade)),
                               style: StrokeStyle(lineWidth: near ? 0.9 : 0.6, lineCap: .round))
                }
            }
        }
        .frame(width: W, height: H)
    }
}

/// A 30 s rain recording looped without a seam (public domain, see the README credits).
@MainActor
final class RainSound {
    private var engine: AVAudioEngine?

    var playing: Bool {
        get { engine != nil }
        set {
            guard newValue != playing else { return }
            if newValue { engine = Self.makeEngine() } else { engine?.stop(); engine = nil }
        }
    }

    private static func makeEngine() -> AVAudioEngine? {
        let dev = URL(fileURLWithPath: "Resources/rain.m4a") // `swift run` from the repo root
        guard let url = Bundle.main.url(forResource: "rain", withExtension: "m4a") ?? (FileManager.default.fileExists(atPath: dev.path) ? dev : nil),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return nil }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.volume = 0.6
        player.scheduleBuffer(buffer, at: nil, options: .loops) // a whole buffer loops gaplessly, unlike a compressed file
        do { try engine.start() } catch { return nil }
        player.play()
        return engine
    }
}
