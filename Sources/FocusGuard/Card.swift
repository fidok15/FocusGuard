import SwiftUI

/// Flat index card standing above the kitchen timer; its tail points down at the timer.
/// Anchored by its bottom edge, so it only ever grows upward and nothing else shifts.
struct SessionCard: View {
    @EnvironmentObject var model: AppModel

    private static let left: CGFloat = 112
    private static let bottom: CGFloat = 220
    private static let tail: CGFloat = 8
    private static let tailX: CGFloat = 57 // local x of the tail tip, centred on the timer dial

    private static func size(_ key: String) -> CGSize {
        switch key {
        case "idle": return CGSize(width: 168, height: 56)
        case "confirm": return CGSize(width: 184, height: 66)
        default: return CGSize(width: 184, height: 112)
        }
    }

    var body: some View {
        let key = model.cardKey
        let size = Self.size(key)
        ZStack {
            CardContent(key: key)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background(CardShape(tailX: Self.tailX, tail: Self.tail).fill(Ink.paper)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2))
                .overlay(CardShape(tailX: Self.tailX, tail: Self.tail).stroke(Ink.pencil.opacity(0.3), lineWidth: 0.6))
                .overlay(alignment: .topLeading) {
                    WashiTape(width: 34, height: 11).rotationEffect(.degrees(-5)).offset(x: size.width - 52, y: -5)
                }
                .padding(.bottom, Self.tail)
                .frame(width: size.width, height: size.height + Self.tail, alignment: .top)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .id(key)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .offset(x: Self.left, y: Self.bottom - size.height)
    }
}

private struct CardShape: Shape {
    let tailX: CGFloat
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let b = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path()
        p.addRoundedRect(in: b, cornerSize: CGSize(width: 3, height: 3))
        p.move(to: CGPoint(x: tailX - 6, y: b.maxY - 0.5))
        p.addLine(to: CGPoint(x: tailX + 1, y: b.maxY + tail))
        p.addLine(to: CGPoint(x: tailX + 7, y: b.maxY - 0.5))
        p.closeSubpath()
        return p
    }
}

// MARK: - Content

private struct CardContent: View {
    @EnvironmentObject var model: AppModel
    let key: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch key {
            case "confirm":
                RuledRow(height: 20) { Text("stop session?").font(Ink.hand(13)) }
                RuledRow(height: 20, seed: 1) {
                    HStack(spacing: 18) {
                        BoxChoice(title: "yes", action: model.stop)
                        BoxChoice(title: "no") { model.confirmStop = false }
                    }
                }
            case "study":
                if case .study(let round) = model.clock.phase {
                    RuledRow(height: 15) { Text("study \(round) of \(model.clock.config.rounds)").font(Ink.hand(11)) }
                }
                RuledRow(height: 31, seed: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        Num(text: model.remainingText)
                        Spacer(minLength: 4)
                        Text("focus").font(Ink.hand(9))
                        Num(text: "\(Int(model.focus.rounded()))%", color: model.focus < 50 ? Ink.red : Ink.ballpoint)
                    }
                }
                RuledRow(height: 22, seed: 2) { Sparkline(values: model.history.suffix(40) + [model.focus]).frame(height: 16) }
                RuledRow(height: 16, seed: 3) { StatusLine() }
            case "rest":
                if case .rest(let round) = model.clock.phase {
                    RuledRow(height: 15) { Text("break \(round) of \(model.clock.config.rounds)").font(Ink.hand(11)) }
                }
                RuledRow(height: 31, seed: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        Num(text: model.remainingText, color: Ink.ballpoint)
                        Spacer(minLength: 4)
                        Text("camera is off").font(Ink.hand(11))
                    }
                }
                RuledRow(height: 18, seed: 2) {
                    Text(model.clock.isPaused ? "paused, tap the mug" : "stretch, drink some water").font(Ink.hand(9))
                }
                RuledRow(height: 18, seed: 3) { EmptyView() }
            case "setup":
                StepRow(label: "study", value: $model.config.studyMinutes, range: 5...90, step: 5, unit: "min", seed: 0)
                StepRow(label: "break", value: $model.config.breakMinutes, range: 1...30, step: 1, unit: "min", seed: 1)
                StepRow(label: "rounds", value: $model.config.rounds, range: 1...8, step: 1, unit: "×", seed: 2)
                RuledRow(height: 26, seed: 3) {
                    HStack(alignment: .lastTextBaseline) {
                        WordLink(title: "start", size: 13, underlined: true, action: model.start)
                        Spacer(minLength: 4)
                        Text("camera only while studying").font(Ink.hand(9)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            case "done":
                RuledRow(height: 18) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("done!").font(Ink.hand(13))
                        Spacer(minLength: 4)
                        Text("nudges: \(model.nudges)").font(Ink.hand(9))
                    }
                }
                RuledRow(height: 31, seed: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("average focus").font(Ink.hand(9))
                        Spacer(minLength: 4)
                        Num(text: "\(model.averageFocus)%")
                    }
                }
                RuledRow(height: 22, seed: 2) { Sparkline(values: model.history).frame(height: 16) }
                RuledRow(height: 18, seed: 3) { WordLink(title: "new session", size: 11, underlined: true, action: model.timerTapped) }
            default:
                RuledRow(height: 18) { Text("Tap the timer").font(Ink.hand(11)) }
                RuledRow(height: 18, seed: 1) { Text("to start studying").font(Ink.hand(11)) }
            }
        }
        .foregroundStyle(Ink.pencil)
    }
}

private struct StatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.clock.isPaused {
                Text("paused, tap the mug")
            } else {
                switch model.camera {
                case .denied: WordLink(title: "allow camera access", size: 9, action: model.openCameraSettings)
                case .unavailable: Text("camera unavailable, retrying…")
                case .starting: Text("starting camera…")
                case .running where model.calibrating: Text("calibrating, look at the screen…")
                case .running, .off: Text("camera on, stays on this Mac")
                }
            }
        }
        .font(Ink.hand(9))
        .foregroundStyle(Ink.pencil)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct StepRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: LocalizedStringKey
    let seed: Double

    var body: some View {
        RuledRow(height: 20, seed: seed) {
            HStack(spacing: 0) {
                Text(label).font(Ink.hand(11)).foregroundStyle(Ink.pencil)
                Spacer(minLength: 4)
                PencilTap(glyph: "−") { value = max(range.lowerBound, value - step) }
                ZStack {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: "\(value)").font(Ink.hand(13)).monospacedDigit()
                        Text(unit).font(Ink.hand(9))
                    }
                    .foregroundStyle(Ink.pencil)
                    LooseEllipse(seed: seed).stroke(Ink.pencil.opacity(0.7), lineWidth: 0.9).padding(.vertical, 1)
                }
                .frame(width: 44, height: 20)
                PencilTap(glyph: "+") { value = min(range.upperBound, value + step) }
            }
        }
    }
}

/// Pencil trace of the focus history, drawn twice with a small offset like a re-gone-over line.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            func line(_ dy: CGFloat, _ seed: Double) -> Path {
                var path = Path()
                for (i, v) in values.enumerated() {
                    let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                    y: size.height * (1 - CGFloat(min(max(v, 0), 100)) / 100) + dy + wob(Double(i), seed) * 0.3)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                return path
            }
            let style = StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round)
            ctx.stroke(line(0, 1), with: .color(Ink.pencil.opacity(0.85)), style: style)
            ctx.stroke(line(0.7, 2), with: .color(Ink.pencil.opacity(0.35)), style: style)
        }
    }
}
