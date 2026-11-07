import SwiftUI

/// Flat index card standing above the kitchen timer; its tail points down at the timer.
/// Anchored by its bottom edge, so it only ever grows upward and nothing else shifts.
struct SessionCard: View {
    @EnvironmentObject var model: AppModel

    private static let tail: CGFloat = 8

    private static func size(_ key: String) -> CGSize {
        switch key {
        case "idle": return CGSize(width: 196, height: 64)
        case "hint": return CGSize(width: 196, height: 108)
        case "why": return CGSize(width: 196, height: 142)
        case "confirm": return CGSize(width: 196, height: 74)
        case "setup": return CGSize(width: 196, height: 132)
        default: return CGSize(width: 196, height: 116)
        }
    }

    var body: some View {
        let key = model.cardKey
        let size = Self.size(key)
        let shape = TornCard(tailX: size.width / 2, tail: Self.tail)
        ZStack {
            CardContent(key: key)
                .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 6)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .background {
                    shape.fill(LinearGradient(colors: [Ink.page, Ink.page.opacity(0.94)], startPoint: .top, endPoint: .bottom))
                        .overlay { Grain().clipShape(shape) }
                        .shadow(color: .black.opacity(0.35), radius: 1.2, y: 1)
                        .shadow(color: .black.opacity(0.22), radius: 6, x: 1, y: 4)
                }
                .overlay(shape.stroke(Ink.pencil.opacity(0.45), style: StrokeStyle(lineWidth: 0.7, lineCap: .round, lineJoin: .round)))
                .overlay(alignment: .topLeading) {
                    WashiTape(width: 34, height: 11).rotationEffect(.degrees(-5)).offset(x: size.width - 48, y: -2)
                }
                .padding(.bottom, Self.tail)
                .frame(width: size.width, height: size.height + Self.tail, alignment: .top)
                .rotationEffect(.degrees(-1.5), anchor: .bottom) // the tail keeps pointing at the clock
                .transition(.opacity.combined(with: .offset(y: 6)).combined(with: .scale(scale: 0.95, anchor: .bottom)))
                .id(key)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .offset(x: Spots.clockTop.x - size.width / 2 - 12, y: Spots.clockTop.y - Self.tail - size.height)
    }
}

/// A page torn out of the notebook: ragged top edge, slightly wobbly sides, a small tail pointing at the timer.
private struct TornCard: Shape {
    let tailX: CGFloat
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let b = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tail)
        var p = Path()
        let n = Int(b.width / 5)
        p.move(to: CGPoint(x: b.minX + 0.5, y: b.maxY))
        p.addLine(to: CGPoint(x: b.minX - 0.4, y: b.minY + 3))
        for i in 0...n { // the tear: small irregular teeth
            let t = CGFloat(i) / CGFloat(n)
            p.addLine(to: CGPoint(x: b.minX + b.width * t + wob(Double(i), 9) * 1.2,
                                  y: b.minY + 2.2 + wob(Double(i), 4) * 1.8 + (i % 3 == 0 ? 0.8 : 0)))
        }
        p.addLine(to: CGPoint(x: b.maxX + 0.4, y: b.minY + 3))
        p.addLine(to: CGPoint(x: b.maxX - 0.3, y: b.maxY - 0.4))
        p.addLine(to: CGPoint(x: tailX + 7, y: b.maxY + 0.3))
        p.addLine(to: CGPoint(x: tailX + 1, y: b.maxY + tail))
        p.addLine(to: CGPoint(x: tailX - 6, y: b.maxY - 0.2))
        p.closeSubpath()
        return p
    }
}

/// Paper tooth: deterministic specks and a few short fibres.
private struct Grain: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<260 {
                let x = (wob(Double(i), 1) + 1) / 2 * size.width, y = (wob(Double(i), 2) + 1) / 2 * size.height
                let r = 0.35 + (wob(Double(i), 3) + 1) * 0.25
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(red: 0.45, green: 0.33, blue: 0.2).opacity(0.09 + 0.08 * Double((wob(Double(i), 5) + 1) / 2))))
            }
            for i in 0..<14 {
                let x = (wob(Double(i), 6) + 1) / 2 * size.width, y = (wob(Double(i), 7) + 1) / 2 * size.height
                var f = Path(); f.move(to: CGPoint(x: x, y: y)); f.addLine(to: CGPoint(x: x + 3 + wob(Double(i), 8) * 2, y: y + wob(Double(i), 9) * 1.5))
                ctx.stroke(f, with: .color(Color(red: 0.5, green: 0.38, blue: 0.24).opacity(0.14)), lineWidth: 0.4)
            }
        }
        .allowsHitTesting(false)
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
                    PhaseHeader(title: "study \(round) of \(model.clock.config.rounds)")
                }
                RuledRow(height: 31, seed: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        Num(text: model.remainingText, color: model.clock.isPaused ? Ink.ballpoint.opacity(0.5) : Ink.ballpoint)
                        Spacer(minLength: 4)
                        if model.showsFocus {
                            Text("focus").font(Ink.hand(11))
                            Num(text: "\(Int(model.focus.rounded()))%", color: model.focus < 50 ? Ink.red : Ink.ballpoint)
                        }
                    }
                }
                RuledRow(height: 22, seed: 2) {
                    if model.showsFocus { Sparkline(values: model.history.suffix(40) + [model.focus]).frame(height: 16) }
                }
                RuledRow(height: 18, seed: 3) {
                    if let nudge = model.nudgeText {
                        Text(verbatim: nudge).font(Ink.hand(11)).foregroundStyle(Ink.red).lineLimit(1).minimumScaleFactor(0.75)
                    } else {
                        StatusLine()
                    }
                }
            case "rest":
                if case .rest(let round) = model.clock.phase {
                    PhaseHeader(title: model.clock.isLongBreak ? "long break \(round) of \(model.clock.config.rounds)"
                                                               : "break \(round) of \(model.clock.config.rounds)")
                }
                RuledRow(height: 34, seed: 1) { Num(text: model.remainingText, color: Ink.ballpoint.opacity(model.clock.isPaused ? 0.5 : 1)) }
                RuledRow(height: 20, seed: 2) {
                    Text(model.clock.isPaused ? pausedLine : String(localized: "stretch, drink some water")).font(Ink.hand(12))
                }
                RuledRow(height: 18, seed: 3) { Text("camera is off").font(Ink.hand(11)).opacity(0.75) }
            case "setup":
                StepRow(label: "study", value: $model.config.studyMinutes, range: 5...90, step: 5, unit: "min", seed: 0)
                StepRow(label: "break", value: $model.config.breakMinutes, range: 1...30, step: 1, unit: "min", seed: 1)
                StepRow(label: "rounds", value: $model.config.rounds, range: 1...8, step: 1, unit: "×", seed: 2)
                RuledRow(height: 26, seed: 3) {
                    HStack {
                        WordLink(title: "start", size: 13, underlined: true, action: model.requestStart)
                        Spacer(minLength: 4)
                        WordLink(title: "done", size: 11) { model.showSetup = false }
                    }
                }
                RuledRow(height: 18, seed: 4) { Text("camera only while studying").font(Ink.hand(11)).lineLimit(1).minimumScaleFactor(0.9) }
            case "why":
                RuledRow(height: 18) { Text("about the camera").font(Ink.hand(12)) }
                Text("FocusGuard looks at you through the camera only while you study. Nothing is saved or sent anywhere.")
                    .font(Ink.hand(12)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading).padding(.top, 5)
                RuledRow(height: 26, seed: 2) {
                    HStack {
                        WordLink(title: "okay, start", size: 12, underlined: true, action: model.confirmCameraWhy)
                        Spacer(minLength: 4)
                        WordLink(title: "timer only", size: 11, action: model.startWithoutCamera)
                    }
                }
            case "done":
                RuledRow(height: 18) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("done!").font(Ink.hand(13))
                        Spacer(minLength: 4)
                        if !model.history.isEmpty { Text("nudges: \(model.nudges)").font(Ink.hand(11)) }
                    }
                }
                RuledRow(height: 31, seed: 1) {
                    HStack(alignment: .lastTextBaseline) {
                        Text("studied").font(Ink.hand(11))
                        Spacer(minLength: 4)
                        Num(text: "\(model.studiedMinutes) min")
                    }
                }
                RuledRow(height: 22, seed: 2) {
                    if let average = model.averageFocus {
                        HStack(alignment: .lastTextBaseline) {
                            Text("average focus").font(Ink.hand(11))
                            Spacer(minLength: 4)
                            Sparkline(values: model.history).frame(width: 60, height: 16)
                            Num(text: "\(average)%", size: 16)
                        }
                    } else {
                        Text("\(model.clock.config.rounds) rounds").font(Ink.hand(12))
                    }
                }
                RuledRow(height: 18, seed: 3) {
                    HStack {
                        WordLink(title: "adjust", size: 12) { model.showSetup = true }
                        Spacer(minLength: 4)
                        WordLink(title: "new session", size: 12, underlined: true, action: model.requestStart)
                    }
                }
            case "hint":
                RuledRow(height: 20) { Text("click the clock to").font(Ink.hand(12)) }
                RuledRow(height: 20, seed: 1) { Text("start a study session").font(Ink.hand(12)) }
                RuledRow(height: 20, seed: 2) { SummaryLine() }
                RuledRow(height: 22, seed: 3) {
                    HStack {
                        WordLink(title: "adjust", size: 12) { model.showSetup = true }
                        Spacer(minLength: 4)
                        WordLink(title: "start", size: 12, underlined: true, action: model.requestStart)
                    }
                }
            default:
                RuledRow(height: 20) { SummaryLine() }
                RuledRow(height: 22, seed: 1) {
                    HStack {
                        WordLink(title: "adjust", size: 12) { model.showSetup = true }
                        Spacer(minLength: 4)
                        WordLink(title: "start", size: 12, underlined: true, action: model.requestStart)
                    }
                }
            }
        }
        .foregroundStyle(Ink.pencil)
    }

    private var pausedLine: String {
        model.pausedBySleep ? String(localized: "paused while you were away") : String(localized: "paused, space to resume")
    }
}

/// "study 2 of 4" with the pause / resume word on the right (the mug does the same).
private struct PhaseHeader: View {
    @EnvironmentObject var model: AppModel
    let title: LocalizedStringKey

    var body: some View {
        RuledRow(height: 17) {
            HStack(spacing: 0) {
                Text(title)
                if model.clock.isPaused { Text("paused").foregroundStyle(Ink.red).padding(.leading, 6) }
                Spacer(minLength: 4)
                WordLink(title: model.clock.isPaused ? "resume" : "pause", size: 12, action: model.togglePause)
            }
            .font(Ink.hand(12))
        }
    }
}

private struct SummaryLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Text(verbatim: model.summary).font(Ink.hand(11)).lineLimit(1).minimumScaleFactor(0.9)
    }
}

private struct StatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.clock.isPaused {
                Text(model.pausedBySleep ? "paused while you were away" : "paused, space to resume")
            } else if model.timerOnly {
                Text("timer only, no camera")
            } else {
                switch model.camera {
                case .denied: WordLink(title: "timer only, allow camera?", size: 11, action: model.openCameraSettings)
                case .unavailable: Text("camera unavailable, retrying…")
                case .starting: Text("starting camera…")
                case .running where model.calibrating: Text("calibrating, look ahead…")
                case .running where model.focusStale: Text("can't see your eyes clearly")
                case .running, .off: Text("camera on, stays on this Mac")
                }
            }
        }
        .font(Ink.hand(11))
        .foregroundStyle(Ink.pencil)
        .lineLimit(1)
        .minimumScaleFactor(0.9)
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
                Text(label).font(Ink.hand(12)).foregroundStyle(Ink.pencil)
                Spacer(minLength: 4)
                PencilTap(glyph: "−") { value = max(range.lowerBound, value - step) }
                    .accessibilityLabel(Text("less \(Text(label))"))
                ZStack {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(verbatim: "\(value)").font(Ink.hand(13)).monospacedDigit()
                        Text(unit).font(Ink.hand(11))
                    }
                    .foregroundStyle(Ink.pencil)
                    LooseEllipse(seed: seed).stroke(Ink.pencil.opacity(0.7), lineWidth: 0.9).padding(.vertical, 1)
                }
                .frame(width: 44, height: 20)
                .accessibilityElement(children: .combine)
                PencilTap(glyph: "+") { value = min(range.upperBound, value + step) }
                    .accessibilityLabel(Text("more \(Text(label))"))
            }
        }
    }
}

/// Pencil trace of the focus history, scaled to its own range (at least 30 points tall), with dots on dips.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let lo = values.min(), let top = values.max() else { return }
            let hi = max(top, lo + 30)
            let pad: CGFloat = 3
            func pt(_ i: Int, _ dy: CGFloat = 0, _ seed: Double = 0) -> CGPoint {
                CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                        y: pad + (size.height - 2 * pad) * (1 - CGFloat((values[i] - lo) / (hi - lo))) + dy + wob(Double(i), seed) * 0.3)
            }
            func line(_ dy: CGFloat, _ seed: Double) -> Path {
                var path = Path()
                for i in values.indices { i == 0 ? path.move(to: pt(i, dy, seed)) : path.addLine(to: pt(i, dy, seed)) }
                return path
            }
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            ctx.stroke(line(0, 1), with: .color(Ink.pencil.opacity(0.9)), style: style)
            ctx.stroke(line(0.8, 2), with: .color(Ink.pencil.opacity(0.3)), style: style)
            for i in 1..<(values.count - 1) where values[i] < values[i - 1] && values[i] <= values[i + 1] && values[i] < 70 {
                let p = pt(i), low = values[i] < 60, r: CGFloat = low ? 2.2 : 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(low ? Ink.red : Ink.pencil))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("focus history"))
        .accessibilityValue(values.last.map { Text(verbatim: "\(Int($0)) %") } ?? Text(verbatim: ""))
    }
}
