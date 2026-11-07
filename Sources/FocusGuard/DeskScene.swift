import AppKit
import AVFoundation
import FocusCore
import SwiftUI

// MARK: - Layout

/// Scene size in points. The art is 2000x1116.
let W: CGFloat = 720
let H: CGFloat = 402
/// Transparent margin around the scene inside the panel, so the drop shadow of the art and its pop-outs is not cut off.
let PAD: CGFloat = 14
/// The opaque picture does not reach the edges of the 2000x1116 canvas, so the panel shows only this part of it (scene points).
let OX: CGFloat = 9, OY: CGFloat = 29.5, CW: CGFloat = 706, CH: CGFloat = 346

/// Art space (2000x1116) to scene points.
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 2000 * W, y: y / 1116 * H) }

/// Rect in the 2000x1116 coordinate space the art was measured in, normalized to 0...1.
private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x / 2000, y: y / 1116, width: w / 2000, height: h / 1116)
}

/// Places that are the same in all four scenes (art coordinates). Everything that differs per scene lives in `Props`.
enum Spots {
    /// Where the card's tail points: the middle of the clock's top edge.
    static let clockTop = P(600, 650)
    static let steam = R(1320, 500, 130, 160)
    static let polaroid = R(1540, 175, 210, 150)
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
    /// Outline of the cat in this scene (art coordinates).
    let silhouette: [CGPoint]
    /// Center and radius of the cat's head (art coordinates), used for the bubble face and the petting effects.
    let head: CGPoint
    let headRadius: CGFloat

    init(url: URL?, silhouette: [CGPoint], head: CGPoint, headRadius: CGFloat) {
        self.url = url
        self.image = url.flatMap(NSImage.init(contentsOf:))
        self.silhouette = silhouette
        self.head = head
        self.headRadius = headRadius
    }

    /// Cat head in scene points.
    var headPoint: CGPoint { P(head.x, head.y) }

    /// Breathing grows the cat upwards from the middle of its underside.
    var anchor: UnitPoint {
        let xs = silhouette.map(\.x), ys = silhouette.map(\.y)
        return UnitPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2 / 2000, y: (ys.max() ?? 0) / 1116)
    }

    /// Round crop of the cat's head, used in the speech bubble. The PNG is 2000 px wide, so art coordinates are pixels.
    var catFace: NSImage? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let full = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let r = headRadius * CGFloat(cg.width) / 2000
        let crop = CGRect(x: head.x * CGFloat(cg.width) / 2000 - r, y: head.y * CGFloat(cg.height) / 1116 - r, width: r * 2, height: r * 2)
        guard let face = cg.cropping(to: crop.intersection(full)) else { return nil }
        let image = NSImage(size: NSSize(width: face.width, height: face.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: face))
        return image
    }

    static func locate(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { return url }
        let dev = URL(fileURLWithPath: "art/\(name).png") // `swift run` from the repo root
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
    var props: Props { self == .day ? .day : self == .sunset ? .sunset : .morning }

    private static let arts: [TimeOfDay: SceneArt] = [
        .morning: SceneArt(url: SceneArt.locate("scene_morning"), silhouette: Silhouette.catMorning,
                           head: CGPoint(x: 1000, y: 612), headRadius: 56),
        .day: SceneArt(url: SceneArt.locate("scene_day"), silhouette: Silhouette.catDay,
                       head: CGPoint(x: 898, y: 552), headRadius: 36),
        .sunset: SceneArt(url: SceneArt.locate("scene_sunset"), silhouette: Silhouette.catSunset,
                          head: CGPoint(x: 1660, y: 655), headRadius: 52),
        .night: SceneArt(url: SceneArt.locate("scene_night"), silhouette: Silhouette.catNight,
                         head: CGPoint(x: 1525, y: 858), headRadius: 60),
    ]
}

// MARK: - Scene

/// What the panel and the debug window show: the scene with a transparent margin for the shadow.
struct PanelRoot: View {
    var body: some View {
        DeskScene().offset(x: -OX, y: -OY).frame(width: CW, height: CH, alignment: .topLeading).padding(PAD)
    }
}

struct DeskScene: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let tod = model.timeOfDay
        ZStack(alignment: .topLeading) {
            Group {
                if let image = tod.art.image {
                    Image(nsImage: image).resizable().frame(width: W, height: H)
                        .shadow(color: .black.opacity(0.4), radius: 7, y: 3) // follows the alpha, pop-outs included
                } else {
                    LinearGradient(colors: [.cyan.opacity(0.4), .brown.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                }
            }
            .id(tod)
            .transition(.opacity)

            CatLayer(art: tod.art).id(tod)

            RecordSpin(image: tod.art.image, props: tod.props).id(tod).allowsHitTesting(false)
            Steam().place(Spots.steam).allowsHitTesting(false)
            ClockDisplay().allowsHitTesting(false)

            Hotspot(name: "clock", groups: [tod.props.clock], help: "Start or stop a study session", action: model.clockTapped)
            Hotspot(name: "mug", groups: [tod.props.mug], help: "Pause / resume", action: model.togglePause)
            Hotspot(name: "sticky", groups: [tod.props.noteLeft, tod.props.noteRight], smooth: false, help: "Settings") {
                model.toggleSettings()
            }
            Hotspot(name: "record", groups: [tod.props.record], help: "Music") { model.musicOn.toggle() }

            if !model.showSettings { SessionCard() } // the note takes the card's place

            if model.showPreview && model.camera == .running {
                Polaroid(session: model.cameraService.session).place(Spots.polaroid)
                    .transition(.scale.combined(with: .opacity))
            }

            if model.showSettings {
                Color.black.opacity(0.001).onTapGesture { model.showSettings = false }
                SettingsNote()
                    .position(x: 128, y: 136)
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }

            QuitButton().position(x: 622, y: 52) // on the top-right corner of the room, above the note's tap catcher
        }
        .frame(width: W, height: H)
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
        .accessibilityElement()
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
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
    private var anchor: UnitPoint { art.anchor }
    /// The cat's outline grown a little and feathered, so the breathing copy blends into the still art without a seam.
    private var breathingMask: some View {
        ZStack {
            catShape.fill(Color.black)
            catShape.stroke(Color.black, style: StrokeStyle(lineWidth: 9, lineJoin: .round))
        }
        .frame(width: W, height: H)
        .blur(radius: 3)
    }

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
                        .mask { breathingMask }
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
                    PetEffects(pets: pets.value, now: context.date, head: art.headPoint)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: H)
        .onAppear {
            #if DEBUG
            if CommandLine.arguments.contains("--autopet") {
                Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in
                    Task { @MainActor in pet(at: CGPoint(x: art.headPoint.x + 30, y: art.headPoint.y), hearts: 3) }
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
                    .position(x: min(head.x + 34, W - 34), y: max(head.y - 44, 14) - CGFloat(min(age, 1)) * 4)
            }
        }
        .frame(width: W, height: H, alignment: .topLeading)
    }
}

// MARK: - Desk objects

/// Three soft wisps rising and fading above the mug. A paused session lets the steam die away.
private struct Steam: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { ctx, size in
                Self.draw(in: &ctx, size: size, time: calmMotion ? 3 : context.date.timeIntervalSinceReferenceDate)
            }
        }
        .opacity(model.clock.isPaused ? 0 : 1)
        .animation(.easeOut(duration: 0.7), value: model.clock.isPaused)
    }

    // Kept out of the view builder with explicit types: older compilers time out type-checking it inline.
    private static func draw(in ctx: inout GraphicsContext, size: CGSize, time t: Double) {
        ctx.addFilter(.blur(radius: 2.5))
        let w = Double(size.width), h = Double(size.height)
        for i in 0..<3 {
            let n = Double(i)
            let phase: Double = (t * 0.22 + n / 3).truncatingRemainder(dividingBy: 1)
            let baseX: Double = w * (0.3 + 0.2 * n)
            var path = Path()
            for k in 0...24 {
                let f: Double = phase * 0.55 + Double(k) / 24 * 0.45 // segment of the column, rising with phase
                let wobble: Double = sin(f * 7 + t * 1.3 + n * 2.1) * w * 0.14 * f
                let point = CGPoint(x: baseX + wobble, y: h * (1 - f))
                if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            let alpha: Double = sin(phase * .pi) * 0.5
            ctx.stroke(path, with: .color(.white.opacity(alpha)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }
}

/// LCD digits on the desk clock's dark glass. Idle: the time with a blinking colon. Study: green countdown.
/// Break: amber countdown. Paused: the countdown blinks. A short flash plays when a session or phase starts.
private struct ClockDisplay: View {
    @EnvironmentObject var model: AppModel

    private static let green = Color(red: 0.55, green: 0.95, blue: 0.62)
    private static let amber = Color(red: 1, green: 0.74, blue: 0.3)

    /// Bounding box of the glass in art coordinates.
    private var box: CGRect {
        let q = model.timeOfDay.props.lcd
        let x0 = q.map(\.x).min()! - 4, y0 = q.map(\.y).min()! - 4
        return CGRect(x: x0, y: y0, width: q.map(\.x).max()! + 4 - x0, height: q.map(\.y).max()! + 4 - y0)
    }

    var body: some View {
        let box = box
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, date: context.date, box: box)
            }
        }
        .frame(width: box.width / 2000 * W, height: box.height / 1116 * H)
        .position(x: box.midX / 2000 * W, y: box.midY / 1116 * H)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, date: Date, box: CGRect) {
        let phase = model.clock.phase, paused = model.clock.isPaused
        let second = date.timeIntervalSinceReferenceDate
        let digits: [Int]
        var colon = true
        switch phase {
        case .idle, .done:
            digits = ClockText.wall(date)
            colon = Int(second.rounded(.down)) % 2 == 0
        case .study, .rest:
            digits = ClockText.countdown(model.remaining)
        }
        let color = phase.isRunning ? (phase.isStudy ? Self.green : Self.amber) : Self.green
        var level = phase.isRunning ? 1.0 : 0.7
        if paused && second - second.rounded(.down) > 0.55 { level = 0.06 } // blink
        let age = date.timeIntervalSince(model.phaseStart)
        let flash = age >= 0 && age < 0.9 && !calmMotion ? (1 - age / 0.9) * abs(sin(age * .pi * 2.6)) : 0

        let scale = size.width / box.width
        let spec = LCDLayout(box: box, lcd: model.timeOfDay.props.lcd, scale: scale)
        // Faint unlit segments, like real LCD glass.
        spec.draw(&ctx, digits: [8, 8, 8, 8], colon: true, color: color.opacity(0.07))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.2 * scale / 0.36))
            spec.draw(&layer, digits: digits, colon: colon, color: color.opacity(0.7 * level + flash))
        }
        spec.draw(&ctx, digits: digits, colon: colon, color: color.opacity(level))
        if flash > 0 {
            ctx.fill(spec.glassPath(), with: .color(color.opacity(0.28 * flash)))
            spec.draw(&ctx, digits: digits, colon: colon, color: .white.opacity(0.8 * flash))
        }
    }
}

/// Seven-segment digits laid out on the clock's sheared glass (art coordinates mapped through the glass quad).
private struct LCDLayout {
    let box: CGRect
    let lcd: [CGPoint]
    let scale: CGFloat

    private let digitW: CGFloat = 36, digitH: CGFloat = 50, thick: CGFloat = 7, slant: CGFloat = 0.12
    private let glassW: CGFloat = 207, glassH: CGFloat = 66

    /// Glass-local coordinates (0...207, 0...66) to canvas points, bilinear over the measured quad.
    private func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let q = lcd, u = x / glassW, v = y / glassH
        let ax = (1 - u) * (1 - v) * q[0].x + u * (1 - v) * q[1].x + u * v * q[2].x + (1 - u) * v * q[3].x
        let ay = (1 - u) * (1 - v) * q[0].y + u * (1 - v) * q[1].y + u * v * q[2].y + (1 - u) * v * q[3].y
        return CGPoint(x: (ax - box.minX) * scale, y: (ay - box.minY) * scale)
    }

    func glassPath() -> Path {
        var p = Path()
        p.move(to: map(0, 0)); p.addLine(to: map(glassW, 0)); p.addLine(to: map(glassW, glassH)); p.addLine(to: map(0, glassH))
        p.closeSubpath()
        return p
    }

    private func poly(_ pts: [CGPoint], dx: CGFloat, dy: CGFloat) -> Path {
        var p = Path()
        for (i, pt) in pts.enumerated() {
            // Italic lean: shift x by how far above the digit's middle the point is.
            let q = map(pt.x + dx + slant * (digitH / 2 - pt.y), pt.y + dy)
            i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        p.closeSubpath()
        return p
    }

    private func segment(_ index: Int, x0: CGFloat, y0: CGFloat) -> Path {
        let t = thick, w = digitW, h = digitH
        func horizontal(_ yc: CGFloat) -> [CGPoint] {
            [CGPoint(x: t * 0.55, y: yc), CGPoint(x: t * 1.1, y: yc - t / 2), CGPoint(x: w - t * 1.1, y: yc - t / 2),
             CGPoint(x: w - t * 0.55, y: yc), CGPoint(x: w - t * 1.1, y: yc + t / 2), CGPoint(x: t * 1.1, y: yc + t / 2)]
        }
        func vertical(_ xc: CGFloat, _ top: CGFloat, _ bottom: CGFloat) -> [CGPoint] {
            [CGPoint(x: xc, y: top + t * 0.55), CGPoint(x: xc + t / 2, y: top + t * 1.05), CGPoint(x: xc + t / 2, y: bottom - t * 1.05),
             CGPoint(x: xc, y: bottom - t * 0.55), CGPoint(x: xc - t / 2, y: bottom - t * 1.05), CGPoint(x: xc - t / 2, y: top + t * 1.05)]
        }
        let pts: [CGPoint]
        switch index {
        case 0: pts = horizontal(t / 2)
        case 1: pts = vertical(w - t / 2, 0, h / 2 + t * 0.3)
        case 2: pts = vertical(w - t / 2, h / 2 - t * 0.3, h)
        case 3: pts = horizontal(h - t / 2)
        case 4: pts = vertical(t / 2, h / 2 - t * 0.3, h)
        case 5: pts = vertical(t / 2, 0, h / 2 + t * 0.3)
        default: pts = horizontal(h / 2)
        }
        return poly(pts, dx: x0, dy: y0)
    }

    func draw(_ ctx: inout GraphicsContext, digits: [Int], colon: Bool, color: Color) {
        let total: CGFloat = 4 * digitW + 2 * 6 + 22
        let left = (glassW - total) / 2 - 2, top = (glassH - digitH) / 2 + 1
        let xs: [CGFloat] = [left, left + digitW + 6, left + 2 * digitW + 6 + 22, left + 3 * digitW + 12 + 22]
        for (i, digit) in digits.enumerated() {
            let mask = SevenSegment.mask(digit)
            for s in 0..<7 where mask & (1 << UInt8(s)) != 0 {
                ctx.fill(segment(s, x0: xs[i], y0: top), with: .color(color))
            }
        }
        if colon {
            let cx = left + 2 * digitW + 6 + 11 - 0.5
            for cy in [top + digitH * 0.32, top + digitH * 0.68] {
                var p = Path()
                for (i, c) in [CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1)].enumerated() {
                    let q = map(cx + c.x * thick * 0.45 + slant * (digitH / 2 - (cy - top)), cy + c.y * thick * 0.45)
                    i == 0 ? p.move(to: q) : p.addLine(to: q)
                }
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            }
        }
    }
}

/// While music is on, the record sheen turns and a few notes drift up from the player. The tonearm stays put.
private struct RecordSpin: View {
    @EnvironmentObject var model: AppModel
    let image: NSImage?
    let props: Props

    private var spinning: Bool { model.musicOn && !calmMotion }

    var body: some View {
        if spinning, let image {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Canvas { ctx, size in
                        draw(in: &ctx, time: context.date.timeIntervalSinceReferenceDate)
                    }
                }
                // Put the arm back on top of the sheen.
                Image(nsImage: image).resizable().frame(width: W, height: H)
                    .mask { OutlineShape(groups: [props.tonearm], smooth: false).fill(Color.black).frame(width: W, height: H) }
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    Notes(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: W, height: H)
            .transition(.opacity)
        }
    }

    /// A point on the disc plane (unit coordinates) projected onto an ellipse in art space, then to scene points.
    private func project(_ e: (center: CGPoint, a: CGFloat, b: CGFloat, tilt: CGFloat), _ radius: CGFloat, _ angle: Double) -> CGPoint {
        let x = e.a * radius * CGFloat(cos(angle)), y = e.b * radius * CGFloat(sin(angle))
        let t = e.tilt * .pi / 180
        return P(e.center.x + x * cos(t) - y * sin(t), e.center.y + x * sin(t) + y * cos(t))
    }

    private func draw(in ctx: inout GraphicsContext, time: Double) {
        let angle = time * 2 * .pi * 0.55 // 33 rpm
        ctx.addFilter(.blur(radius: 1.2))
        // Two soft light wedges across the grooves.
        for (offset, width, strength) in [(0.0, 0.75, 0.5), (.pi * 0.95, 0.45, 0.32)] {
            var wedge = Path()
            let a0 = angle + offset, a1 = a0 + width
            wedge.move(to: project(props.vinyl, 0.4, a0))
            for k in 0...10 { wedge.addLine(to: project(props.vinyl, 0.97, a0 + (a1 - a0) * Double(k) / 10)) }
            wedge.addLine(to: project(props.vinyl, 0.4, a1))
            wedge.closeSubpath()
            ctx.fill(wedge, with: .color(Color(red: 0.85, green: 0.9, blue: 1).opacity(strength)))
        }
        // A scuff on the label, to see the turning.
        var tick = Path()
        tick.move(to: project(props.label, 0.55, angle * 1.0 + 1.2))
        tick.addLine(to: project(props.label, 0.9, angle * 1.0 + 1.2))
        ctx.stroke(tick, with: .color(Ink.pencil.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private struct Notes: View {
        let time: Double

        var body: some View {
            ZStack(alignment: .topLeading) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (time * 0.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let base = P(130, 620)
                    Image(systemName: i == 1 ? "music.quarternote.3" : "music.note")
                        .font(.system(size: 11 + CGFloat(i) * 1.5, weight: .bold))
                        .foregroundStyle(Ink.pencil)
                        .shadow(color: .white.opacity(0.7), radius: 1.5)
                        .opacity(calmMotion ? 0.8 : sin(phase * .pi) * 0.9)
                        .position(x: base.x + CGFloat(phase) * 30 + CGFloat(sin(phase * 9 + Double(i) * 2)) * 4 + CGFloat(i) * 16,
                                  y: base.y - CGFloat(phase) * 70 - CGFloat(i) * 6)
                }
            }
            .frame(width: W, height: H, alignment: .topLeading)
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
