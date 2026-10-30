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
enum Spots {
    static let timer = R(375, 640, 175, 185)
    static let dial = R(418, 683, 104, 104)
    static let leftPage = R(684, 818, 308, 180)
    static let rightPage = R(1014, 818, 312, 180)
    static let mug = R(1390, 680, 165, 155)
    static let steam = R(1400, 540, 110, 150)
    static let stickyNotes = R(1475, 860, 265, 85)
    static let polaroid = R(40, 40, 240, 215)
}

extension View {
    /// Sizes and positions a view at a normalized scene rect.
    func place(_ r: CGRect) -> some View {
        frame(width: r.width * W, height: r.height * H).position(x: r.midX * W, y: r.midY * H)
    }
}

enum Ink {
    static let pencil = Color(red: 0.227, green: 0.208, blue: 0.188)
    static let line = Color(red: 0.36, green: 0.24, blue: 0.16)
    static let page = Color(red: 0.98, green: 0.945, blue: 0.84) // notebook page tone, sampled from the art
    static let paper = Color(red: 1, green: 0.97, blue: 0.9)
    static let sticky = Color(red: 0.965, green: 0.886, blue: 0.478)
    static let red = Color(red: 0.824, green: 0.318, blue: 0.247)
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
    var silhouette: [CGPoint] = []

    init(url: URL?, cat: CGRect, head: CGPoint, headRadius: CGFloat, silhouette: [CGPoint] = []) {
        self.silhouette = silhouette
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
                           head: CGPoint(x: 905.0 / 2000, y: 512.0 / 1116), headRadius: 0.035, silhouette: Silhouette.catMorning),
        .day: SceneArt(url: SceneArt.locate("scene_day"), cat: R(1715, 495, 285, 270),
                       head: CGPoint(x: 1785.0 / 2000, y: 560.0 / 1116), headRadius: 0.035, silhouette: Silhouette.catDay),
        .sunset: SceneArt(url: SceneArt.locate("scene_sunset"), cat: R(1305, 265, 240, 350),
                          head: CGPoint(x: 1420.0 / 2000, y: 320.0 / 1116), headRadius: 0.033, silhouette: Silhouette.catSunset),
        .night: SceneArt(url: SceneArt.locate("scene_night"), cat: R(40, 750, 505, 265),
                         head: CGPoint(x: 445.0 / 2000, y: 860.0 / 1116), headRadius: 0.038, silhouette: Silhouette.catNight),
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

            Hotspot(name: "timer", groups: [Silhouette.timer], help: "Set study time", action: model.timerTapped)
            Hotspot(name: "mug", groups: [Silhouette.mug], help: "Pause / resume", action: model.togglePause)
            Hotspot(name: "sticky", groups: [Silhouette.pinkNote, Silhouette.greenNote], smooth: false, help: "Settings") {
                model.showSettings.toggle()
                model.showSetup = false
            }

            SessionCard()

            if model.showPreview && model.camera == .running {
                Polaroid(session: model.cameraService.session).place(Spots.polaroid)
                    .transition(.scale.combined(with: .opacity))
            }

            QuitButton().position(x: W - 21, y: 21)

            if model.showSettings {
                Color.black.opacity(0.001).onTapGesture { model.showSettings = false }
                SettingsNote()
                    .position(x: W * 0.8, y: H * 0.755)
                    .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(width: W, height: H)
        .clipped()
        .fixedSize()
        .coordinateSpace(name: "scene")
        .animation(.easeInOut(duration: 1.2), value: tod)
        .animation(.spring(duration: 0.3), value: model.showSettings)
        .animation(.spring(duration: 0.3), value: model.showPreview && model.camera == .running)
        .animation(.easeOut(duration: 0.25), value: model.cardKey)
    }
}

/// Invisible clickable area shaped exactly like an object in the art, with a soft glow on hover.
private struct Hotspot: View {
    let name: String
    let groups: [[CGPoint]]
    var smooth = true
    let help: LocalizedStringKey
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        let shape = OutlineShape(groups: groups, smooth: smooth)
        ZStack {
            HoverGlow(shape: shape, on: hover.value || forcedHover?.contains(name) == true)
            shape.fill(Color.white.opacity(0.001))
        }
        .frame(width: W, height: H)
        .contentShape(shape)
        .onHover { inside in
            hover.value = inside
            inside ? NSCursor.pointingHand.push() : NSCursor.pop()
        }
        .onDisappear { if hover.value { NSCursor.pop(); hover.value = false } }
        .onTapGesture(perform: action)
        .help(help)
    }
}

// MARK: - Cat

private struct Pet: Identifiable {
    let id = UUID()
    let born: Date
    let points: [CGPoint]
    let drifts: [CGFloat]
}

private var calmMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// Cuts the cat out of the art with a soft mask so it can breathe and react to petting.
/// All motion is a pure function of the clock, so nothing can capture the window's own layout animation.
private struct CatLayer: View {
    let art: SceneArt
    @StateObject private var pets = Box<[Pet]>([])
    @StateObject private var lastPoint = Box<CGPoint?>(nil)
    @StateObject private var hovering = Box(false)
    @StateObject private var stroke = Box<CGFloat>(0)

    private var catShape: OutlineShape { OutlineShape(groups: [art.silhouette]) }
    private var anchor: UnitPoint { UnitPoint(x: art.cat.midX, y: art.cat.maxY) }

    /// Damped bounce after a pet: positive = squashed.
    private func squish(at date: Date) -> CGFloat {
        guard let last = pets.value.last else { return 0 }
        let dt = date.timeIntervalSince(last.born)
        guard dt >= 0, dt < 1.4 else { return 0 }
        return CGFloat(exp(-5 * dt) * sin(2 * .pi * 3.2 * dt + 0.5) * 1.1)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image = art.image {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let b: CGFloat = calmMotion ? 0 : CGFloat((1 - cos(t * 2 * .pi / 4.6)) / 2)
                    let s = calmMotion ? 0 : squish(at: context.date)
                    Image(nsImage: image).resizable().frame(width: W, height: H)
                        .scaleEffect(x: 1 + 0.004 * b + 0.016 * s, y: 1 + 0.014 * b - 0.026 * s, anchor: anchor)
                        .mask { Ellipse().place(art.cat.insetBy(dx: -0.012, dy: -0.012)).blur(radius: 8) }
                }
                .allowsHitTesting(false)
            }

            HoverGlow(shape: catShape, on: hovering.value || forcedHover?.contains("cat") == true)
            catShape.fill(Color.white.opacity(0.001))
                .onHover { inside in
                    hovering.value = inside
                    inside ? NSCursor.openHand.push() : NSCursor.pop()
                }
                .onDisappear { if hovering.value { NSCursor.pop(); hovering.value = false } }
                .gesture(petting)
                .help("Pet the cat")

            if !pets.value.isEmpty {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    PetEffects(pets: pets.value, now: context.date, head: art.head)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: H)
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("--autopet") {
                Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
                    Task { @MainActor in pet(at: CGPoint(x: art.head.x * W + 30, y: art.head.y * H), hearts: 3) }
                }
            }
            #endif
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
        let pts = (0..<count).map { CGPoint(x: point.x + CGFloat($0 - count / 2) * 12, y: point.y - 6) }
        let new = Pet(born: Date(), points: pts, drifts: pts.map { _ in .random(in: -14...14) })
        pets.value.append(new)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { pets.value.removeAll { $0.id == new.id } }
    }
}

/// Hearts rising off the cat and a hand-lettered "prrr~", all derived from each pet's age.
private struct PetEffects: View {
    let pets: [Pet]
    let now: Date
    let head: CGPoint

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pets) { pet in
                let age = now.timeIntervalSince(pet.born)
                let p = CGFloat(min(max(age / 1.2, 0), 1))
                ForEach(Array(pet.points.enumerated()), id: \.offset) { i, point in
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.6))
                        .shadow(color: .white.opacity(0.8), radius: 1)
                        .scaleEffect(0.5 + 0.8 * p)
                        .opacity(Double(1 - p))
                        .position(x: point.x + pet.drifts[i] * p, y: point.y - 48 * (1 - (1 - p) * (1 - p)))
                }
            }
            if let last = pets.last {
                let age = now.timeIntervalSince(last.born)
                let a = min(age / 0.15, 1) * min(max((1.6 - age) / 0.4, 0), 1)
                Text("prrr~")
                    .font(Ink.hand(12))
                    .foregroundStyle(Ink.pencil)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Ink.page, in: RoundedRectangle(cornerRadius: 1.5))
                    .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Ink.pencil.opacity(0.5), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .rotationEffect(.degrees(-4))
                    .opacity(a)
                    .position(x: head.x * W + 48, y: head.y * H - 58 - CGFloat(min(age, 1)) * 4)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
    }
}

// MARK: - Desk objects

/// Three soft wisps rising and fading above the mug.
private struct Steam: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                Self.draw(in: &ctx, size: size, time: calmMotion ? 3 : context.date.timeIntervalSinceReferenceDate)
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

/// Red wedge of remaining time on the kitchen timer dial (green during breaks). Sweeps in once when a session starts.
private struct TimerFace: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let settled = Date().timeIntervalSince(model.phaseStart) > 0.8
        TimelineView(.animation(minimumInterval: 1 / 30, paused: settled)) { context in
            Canvas { ctx, size in
                guard model.clock.phase.isRunning else { return }
                let age = context.date.timeIntervalSince(model.phaseStart)
                let u = calmMotion ? 1 : min(max(age / 0.6, 0), 1)
                let sweep = 1 - (1 - u) * (1 - u) * (1 - u)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 * 0.82
                let end = Angle.degrees(-90 + 360 * model.remainingFraction * sweep)
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
}

// MARK: - Preview

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
