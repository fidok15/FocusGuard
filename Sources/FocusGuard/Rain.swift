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

/// Soft rain made on the fly, so no audio file ships: band-passed noise for the wash and short random ticks for the drops.
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

    private nonisolated static func makeEngine() -> AVAudioEngine? {
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate > 0 ? rate : 44100, channels: 2) else { return nil }
        let synth = RainSynth(rate: Float(format.sampleRate))
        let source = AVAudioSourceNode(format: format) { _, _, frames, list in
            synth.render(Int(frames), into: UnsafeMutableAudioBufferListPointer(list))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return nil }
        return engine
    }
}

/// Runs on the audio thread only.
private final class RainSynth: @unchecked Sendable {
    private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    private var high: [Float] = [0, 0], low: [Float] = [0, 0], drop: [Float] = [0, 0], last: [Float] = [0, 0]
    private let dropChance: Float, dropDecay: Float

    init(rate: Float) {
        dropChance = 45 / rate // drops per second, per ear
        dropDecay = exp(-1 / (0.006 * rate))
    }

    private func random() -> Float {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Float(seed >> 40) / Float(1 << 24)
    }

    func render(_ frames: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        for c in 0..<min(2, buffers.count) {
            guard let out = buffers[c].mData?.assumingMemoryBound(to: Float.self) else { continue }
            for i in 0..<frames {
                let white = random() * 2 - 1
                high[c] += 0.25 * (white - high[c]) // ~1.8 kHz low-pass
                low[c] += 0.02 * (white - low[c]) // ~140 Hz: what is left between them is the wash
                if random() < dropChance { drop[c] = 0.3 + 0.7 * random() }
                drop[c] *= dropDecay
                out[i] = ((high[c] - low[c]) * 0.5 + (white - last[c]) * drop[c] * 0.25) * 0.3
                last[c] = white
            }
        }
    }
}
