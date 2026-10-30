import AppKit
import AVFoundation
import FocusCore
import SwiftUI

// MARK: - Layout

/// Scene size in points. The art is 16:9-ish (2752×1536).
let W: CGFloat = 720
let H: CGFloat = 402

/// Rect in the 2000×1116 coordinate space the art was measured in, normalized to 0…1.
private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x / 2000, y: y / 1116, width: w / 2000, height: h / 1116)
}

/// Objects drawn in the same place in all four scenes.
private enum Spots {
    static let timer = R(375, 640, 175, 185)
    static let dial = R(418, 683, 104, 104)
    static let leftPage = R(684, 818, 308, 180)
    static let rightPage = R(1014, 818, 312, 180)
    static let mug = R(1390, 680, 165, 155)
    static let steam = R(1400, 540, 110, 150)
    static let stickyNotes = R(1475, 860, 265, 85)
    static let polaroid = R(40, 40, 240, 215)
}

private extension View {
    /// Sizes and positions a view at a normalized scene rect.
    func place(_ r: CGRect) -> some View {
        frame(width: r.width * W, height: r.height * H).position(x: r.midX * W, y: r.midY * H)
    }
}

enum Ink {
    static let pencil = Color(red: 0.24, green: 0.2, blue: 0.18)
    static let line = Color(red: 0.36, green: 0.24, blue: 0.16)
    static let paper = Color(red: 1, green: 0.97, blue: 0.9)
    static let sticky = Color(red: 1, green: 0.94, blue: 0.62)
    static let red = Color(red: 0.86, green: 0.3, blue: 0.27)
    static let green = Color(red: 0.3, green: 0.56, blue: 0.43)
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
}

/// Plain view state. `@State` is a macro in the macOS 27 SDK and its plugin ships only with Xcode;
/// this keeps the app buildable with the Command Line Tools alone.
final class Box<T>: ObservableObject {
    @Published var value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Art

struct SceneArt {
    let url: URL?
    let image: NSImage?
    /// Where the cat lies in this scene (normalized).
    let cat: CGRect
    let head: CGPoint
    let headRadius: CGFloat

    init(url: URL?, cat: CGRect, head: CGPoint, headRadius: CGFloat) {
        self.url = url
        self.image = url.flatMap(NSImage.init(contentsOf:))
        self.cat = cat
        self.head = head
        self.headRadius = headRadius
    }

    /// Round crop of the cat's head, used in the speech bubble.
    var catFace: NSImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let pw = CGFloat(cg.width), ph = CGFloat(cg.height), r = headRadius * pw
        let crop = CGRect(x: head.x * pw - r, y: head.y * ph - r, width: r * 2, height: r * 2)
        guard let face = cg.cropping(to: crop) else { return nil }
        let image = NSImage(size: crop.size)
        image.addRepresentation(NSBitmapImageRep(cgImage: face))
        return image
    }

    static func locate(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") { return url }
        let dev = URL(fileURLWithPath: "art/\(name).jpeg") // `swift run` from the repo root
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}

enum TimeOfDay: CaseIterable {
    case morning, day, sunset, night

    init(date: Date) {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<9: self = .morning
        case 9..<17: self = .day
        case 17..<20: self = .sunset
        default: self = .night
        }
    }

    var art: SceneArt { Self.arts[self]! }

    private static let arts: [TimeOfDay: SceneArt] = [
        .morning: SceneArt(url: SceneArt.locate("scene_morning"), cat: R(815, 425, 405, 180),
                           head: CGPoint(x: 905.0 / 2000, y: 512.0 / 1116), headRadius: 0.035),
        .day: SceneArt(url: SceneArt.locate("scene_day"), cat: R(1715, 495, 285, 270),
                       head: CGPoint(x: 1785.0 / 2000, y: 560.0 / 1116), headRadius: 0.035),
        .sunset: SceneArt(url: SceneArt.locate("scene_sunset"), cat: R(1305, 265, 240, 350),
                          head: CGPoint(x: 1420.0 / 2000, y: 320.0 / 1116), headRadius: 0.033),
        .night: SceneArt(url: SceneArt.locate("scene_night"), cat: R(40, 750, 505, 265),
                         head: CGPoint(x: 445.0 / 2000, y: 860.0 / 1116), headRadius: 0.038),
    ]
}

// MARK: - Scene

struct DeskScene: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tod = model.timeOfDay
        ZStack(alignment: .topLeading) {
            Group {
                if let image = tod.art.image {
                    Image(nsImage: image).resizable().frame(width: W, height: H)
                } else {
                    LinearGradient(colors: [.cyan.opacity(0.4), .brown.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                }
            }
            .id(tod)
            .transition(.opacity)

            CatLayer(art: tod.art).id(tod)

            Steam().place(Spots.steam).allowsHitTesting(false)
            TimerFace().place(Spots.dial).allowsHitTesting(false)

            Hotspot(rect: Spots.timer, help: "Set study time", action: model.timerTapped)
            Hotspot(rect: Spots.mug, help: "Pause / resume", action: model.togglePause)
            Hotspot(rect: Spots.stickyNotes, help: "Settings") {
                model.showSettings.toggle()
                model.showSetup = false
            }

            LeftPage().place(Spots.leftPage)
            RightPage().place(Spots.rightPage)

            if model.showPreview && model.camera == .running {
                Polaroid(session: model.cameraService.session).place(Spots.polaroid)
                    .transition(.scale.combined(with: .opacity))
            }

            QuitButton().position(x: W - 18, y: 18)

            if model.showSettings {
                Color.black.opacity(0.001).onTapGesture { model.showSettings = false }
                SettingsNote()
                    .position(x: W * 0.79, y: H * 0.58)
                    .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(width: W, height: H)
        .clipped()
        .coordinateSpace(name: "scene")
        .animation(.easeInOut(duration: 1.2), value: tod)
        .animation(.spring(duration: 0.3), value: model.showSettings)
        .animation(.spring(duration: 0.3), value: model.showPreview && model.camera == .running)
    }
}

/// Invisible clickable area over an object in the art, with a soft glow on hover.
private struct Hotspot: View {
    let rect: CGRect
    let help: LocalizedStringKey
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(hover.value ? 0.12 : 0.001))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(hover.value ? 0.6 : 0), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(Rectangle())
            .onHover { inside in
                hover.value = inside
                inside ? NSCursor.pointingHand.push() : NSCursor.pop()
            }
            .onDisappear { if hover.value { NSCursor.pop(); hover.value = false } }
            .onTapGesture(perform: action)
            .help(help)
            .animation(.easeOut(duration: 0.15), value: hover.value)
            .place(rect)
    }
}

// MARK: - Cat

private struct Heart: Identifiable {
    let id = UUID()
    let point: CGPoint
    let drift: CGFloat
}

/// Cuts the cat out of the art with a soft mask so it can breathe and react to petting.
private struct CatLayer: View {
    let art: SceneArt
    @StateObject private var breathe = Box(false)
    @StateObject private var squish = Box(false)
    @StateObject private var hearts = Box<[Heart]>([])
    @StateObject private var purrs = Box(0)
    @StateObject private var lastPoint = Box<CGPoint?>(nil)
    @StateObject private var hovering = Box(false)
    @StateObject private var stroke = Box<CGFloat>(0)

    private var anchor: UnitPoint { UnitPoint(x: art.cat.midX, y: art.cat.maxY) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = art.image {
                Image(nsImage: image).resizable().frame(width: W, height: H)
                    .scaleEffect(x: 1 + (breathe.value ? 0.006 : 0) + (squish.value ? 0.018 : 0),
                                 y: 1 + (breathe.value ? 0.022 : 0) - (squish.value ? 0.03 : 0),
                                 anchor: anchor)
                    .mask {
                        Ellipse().place(art.cat.insetBy(dx: -0.01, dy: -0.01)).blur(radius: 6)
                    }
                    .allowsHitTesting(false)
            }

            Ellipse().fill(Color.white.opacity(0.001))
                .onHover { inside in
                    hovering.value = inside
                    inside ? NSCursor.openHand.push() : NSCursor.pop()
                }
                .onDisappear { if hovering.value { NSCursor.pop(); hovering.value = false } }
                .gesture(petting)
                .help("Pet the cat")
                .place(art.cat)

            ForEach(hearts.value) { HeartView(heart: $0) }.allowsHitTesting(false)

            if purrs.value > 0 {
                Text("prrr~ ♡")
                    .font(Ink.hand(13))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .position(x: art.head.x * W + 26, y: art.head.y * H - 30)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: H)
        .animation(.easeOut(duration: 0.3), value: purrs.value > 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe.value = true }
        }
    }

    private var petting: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("scene"))
            .onChanged { value in
                if let last = lastPoint.value { stroke.value += hypot(value.location.x - last.x, value.location.y - last.y) }
                lastPoint.value = value.location
                if stroke.value > 26 {
                    stroke.value = 0
                    pet(at: value.location, hearts: 1)
                }
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) < 4 { pet(at: value.location, hearts: 3) }
                lastPoint.value = nil
                stroke.value = 0
            }
    }

    private func pet(at point: CGPoint, hearts count: Int) {
        let new = (0..<count).map { i in
            Heart(point: CGPoint(x: point.x + CGFloat(i - count / 2) * 12, y: point.y - 6), drift: .random(in: -14...14))
        }
        hearts.value += new
        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) { squish.value = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { squish.value = false }
        }
        purrs.value += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { purrs.value -= 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            hearts.value.removeAll { h in new.contains { $0.id == h.id } }
        }
    }
}

private struct HeartView: View {
    let heart: Heart
    @StateObject private var up = Box(false)

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 13))
            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.6))
            .shadow(color: .white.opacity(0.8), radius: 1)
            .scaleEffect(up.value ? 1.3 : 0.5)
            .offset(x: up.value ? heart.drift : 0, y: up.value ? -48 : 0)
            .opacity(up.value ? 0 : 1)
            .position(heart.point)
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { up.value = true } }
    }
}

// MARK: - Desk objects

/// Three soft wisps rising and fading above the mug.
private struct Steam: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                Self.draw(in: &ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    // Kept out of the view builder with explicit types: older compilers time out type-checking it inline.
    private static func draw(in ctx: inout GraphicsContext, size: CGSize, time t: Double) {
        ctx.addFilter(.blur(radius: 2.5))
        let w = Double(size.width), h = Double(size.height)
        for i in 0..<3 {
            let n = Double(i)
            let phase: Double = (t * 0.22 + n / 3).truncatingRemainder(dividingBy: 1)
            let baseX: Double = w * (0.32 + 0.16 * n)
            var path = Path()
            for k in 0...24 {
                let f: Double = phase * 0.55 + Double(k) / 24 * 0.45 // segment of the column, rising with phase
                let wobble: Double = sin(f * 7 + t * 1.3 + n * 2.1) * w * 0.16 * f
                let point = CGPoint(x: baseX + wobble, y: h * (1 - f))
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let alpha: Double = sin(phase * .pi) * 0.5
            ctx.stroke(path, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }
}

/// Red wedge of remaining time on the kitchen timer dial (green during breaks).
private struct TimerFace: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Canvas { ctx, size in
            guard model.clock.phase.isRunning else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 * 0.82
            let end = Angle.degrees(-90 + 360 * model.remainingFraction)
            var wedge = Path()
            wedge.move(to: c)
            wedge.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: end, clockwise: false)
            wedge.closeSubpath()
            let color = model.clock.phase.isStudy ? Ink.red : Ink.green
            ctx.fill(wedge, with: .color(color.opacity(model.clock.isPaused ? 0.4 : 0.78)))
            var hand = Path()
            hand.move(to: c)
            hand.addLine(to: CGPoint(x: c.x + cos(end.radians) * r, y: c.y + sin(end.radians) * r))
            ctx.stroke(hand, with: .color(Ink.pencil), lineWidth: 1.5)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 2.5, width: 5, height: 5)), with: .color(Ink.pencil))
        }
    }
}

// MARK: - Notebook

private struct LeftPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch model.clock.phase {
            case _ where model.confirmStop:
                Text("Stop session?").font(Ink.hand(13))
                HStack(spacing: 14) {
                    Link("Yes", action: model.stop)
                    Link("No") { model.confirmStop = false }
                }
            case .study(let round):
                Text("Study \(round)/\(model.clock.config.rounds)").font(Ink.hand(10))
                Text(verbatim: model.remainingText).font(Ink.hand(20)).monospacedDigit()
                StatusLine()
            case .rest(let round):
                Text("Break \(round)/\(model.clock.config.rounds)").font(Ink.hand(10))
                Text(verbatim: model.remainingText).font(Ink.hand(20)).monospacedDigit()
                if model.clock.isPaused { Text("Paused – tap the mug").font(Ink.hand(9)) }
            case .idle, .done:
                if model.showSetup {
                    SetupRow(label: "Study", value: $model.config.studyMinutes, range: 5...90, step: 5, unit: "min")
                    SetupRow(label: "Break", value: $model.config.breakMinutes, range: 1...30, step: 1, unit: "min")
                    SetupRow(label: "Rounds", value: $model.config.rounds, range: 1...8, step: 1, unit: "×")
                } else if model.clock.phase == .done {
                    Text("Done! ✿").font(Ink.hand(13))
                    Text("Average focus").font(Ink.hand(10))
                    Text(verbatim: "\(model.averageFocus)%").font(Ink.hand(20))
                } else {
                    Text(verbatim: "FocusGuard").font(Ink.hand(14))
                    Text("Tap the timer").font(Ink.hand(10))
                    Text("to start studying").font(Ink.hand(10))
                }
            }
        }
        .foregroundStyle(Ink.pencil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 15).padding(.trailing, 4)
    }
}

private struct RightPage: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch model.clock.phase {
            case .study:
                HStack(alignment: .firstTextBaseline) {
                    Text("Focus").font(Ink.hand(10))
                    Text(verbatim: "\(Int(model.focus.rounded()))%").font(Ink.hand(20)).monospacedDigit()
                        .foregroundStyle(model.focus < 50 ? Ink.red : Ink.pencil)
                }
                Sparkline(values: model.history.suffix(40) + [model.focus]).frame(height: 22)
            case .rest:
                Text("Camera is off").font(Ink.hand(11))
                Text("Stretch, drink some water ☕").font(Ink.hand(9))
            case .idle, .done:
                if model.showSetup {
                    Link("Start ▶", action: model.start).font(Ink.hand(18))
                    Text("Camera works only while studying").font(Ink.hand(8))
                } else if model.clock.phase == .done {
                    Sparkline(values: model.history).frame(height: 20).padding(.top, 6)
                    Text("Nudges: \(model.nudges)").font(Ink.hand(10))
                    Text("Tap the timer for a new session").font(Ink.hand(8)).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Pet the cat ♡").font(Ink.hand(10)).opacity(0.75)
                }
            }
        }
        .foregroundStyle(Ink.pencil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 12).padding(.trailing, 6)
    }
}

private struct StatusLine: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if model.clock.isPaused {
                Text("Paused – tap the mug")
            } else {
                switch model.camera {
                case .denied: Link("No camera access →", action: model.openCameraSettings)
                case .unavailable: Text("Camera unavailable, retrying…")
                case .starting: Text("Starting camera…")
                case .running where model.calibrating: Text("Calibrating, look at the screen…")
                case .running, .off: Text("Camera on · stays on this Mac")
                }
            }
        }
        .font(Ink.hand(8))
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SetupRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: LocalizedStringKey

    var body: some View {
        HStack(spacing: 0) {
            Text(label).font(Ink.hand(10)).fixedSize()
            Spacer(minLength: 2)
            Link("−", hitWidth: 16) { value = max(range.lowerBound, value - step) }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: "\(value)").font(Ink.hand(12)).monospacedDigit()
                Text(unit).font(Ink.hand(7))
            }
            .fixedSize()
            .frame(minWidth: 26)
            Link("+", hitWidth: 16) { value = min(range.upperBound, value + step) }
        }
        .frame(height: 17)
    }
}

/// Pencil-style text button.
private struct Link: View {
    let title: LocalizedStringKey
    var hitWidth: CGFloat? = nil
    let action: () -> Void
    @StateObject private var hover = Box(false)

    init(_ title: LocalizedStringKey, hitWidth: CGFloat? = nil, action: @escaping () -> Void) {
        self.title = title
        self.hitWidth = hitWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Ink.hand(12))
                .underline(hover.value && hitWidth == nil)
                .foregroundStyle(hover.value ? Ink.red : Ink.pencil)
                .frame(minWidth: hitWidth, minHeight: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.12), value: hover.value)
    }
}

/// Small tactile press: scale to 0.96, quick ease-out.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: size.height * (1 - CGFloat(min(max(v, 0), 100)) / 100))
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            ctx.stroke(path, with: .color(Ink.pencil.opacity(0.8)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Settings and preview

/// Always-visible way out: menu bar apps have no Dock icon or app menu. Also bound to ⌘Q.
private struct QuitButton: View {
    @StateObject private var hover = Box(false)

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "power")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(hover.value ? 1 : 0.75))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(hover.value ? 0.45 : 0.25)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut("q")
        .onHover { hover.value = $0 }
        .help("Quit FocusGuard")
        .animation(.easeOut(duration: 0.12), value: hover.value)
    }
}

private struct SettingsNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings").font(Ink.hand(14))
            Text("Alert sensitivity").font(Ink.hand(10))
            Slider(value: $model.sensitivity, in: 0...1).controlSize(.mini).tint(Ink.line)
            HStack {
                Text("gentle")
                Spacer()
                Text("sensitive")
            }.font(Ink.hand(8))
            Toggle(isOn: $model.showPreview) { Text("Camera preview").font(Ink.hand(10)) }
                .toggleStyle(.checkbox)
            Link("Quit FocusGuard") { NSApp.terminate(nil) }
        }
        .foregroundStyle(Ink.pencil)
        .padding(12)
        .frame(width: 190)
        .background(Ink.sticky.shadow(.drop(color: .black.opacity(0.3), radius: 5, y: 3)))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.55)).frame(width: 54, height: 14).rotationEffect(.degrees(-4)).offset(y: -7)
        }
        .rotationEffect(.degrees(-2))
    }
}

private struct Polaroid: View {
    let session: AVCaptureSession

    var body: some View {
        CameraPreview(session: session)
            .scaleEffect(x: -1, y: 1)
            .clipShape(Rectangle())
            .padding(.horizontal, 5).padding(.top, 5).padding(.bottom, 14)
            .background(Color.white.shadow(.drop(color: .black.opacity(0.35), radius: 3, y: 2)))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.6)).frame(width: 30, height: 9).offset(y: -4)
            }
            .rotationEffect(.degrees(-4))
    }
}

private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
