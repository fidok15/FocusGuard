import SwiftUI

/// Pseudo-random but deterministic wobble in -1…1, so every hand-drawn mark looks the same on each redraw.
func wob(_ i: Double, _ seed: Double) -> CGFloat {
    let v = sin(i * 12.9898 + seed * 78.233) * 43758.5453
    return CGFloat((v - v.rounded(.down)) * 2 - 1)
}

/// Fonts and colours of the things "written" on the desk.
extension Ink {
    static let ballpoint = Color(red: 0.173, green: 0.243, blue: 0.361)
    static let washi = Color(red: 0.612, green: 0.788, blue: 0.706)
    static let ruled = Color(red: 0.616, green: 0.706, blue: 0.812).opacity(0.35)
    static func num(_ size: CGFloat) -> Font { .custom("BradleyHandITCTT-Bold", size: size) }
}

/// A ruler-free line with a little hand tremble.
struct PencilLine: Shape {
    var seed: Double = 0
    var amp: CGFloat = 0.6

    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(2, Int(r.width / 9))
        for i in 0...n {
            let pt = CGPoint(x: r.minX + r.width * CGFloat(i) / CGFloat(n), y: r.midY + wob(Double(i), seed) * amp)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// Underline drawn as a loose wave (trim it to animate the stroke being drawn).
struct WavyLine: Shape {
    var seed: Double = 1

    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(4, Int(r.width / 2))
        for i in 0...n {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(n)
            let y = r.midY + CGFloat(sin(Double(i) * 0.9 + seed)) * 1.3 + wob(Double(i), seed) * 0.2
            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}

/// Short zig-zag scribble, used as a hover mark under − and +.
struct Scribble: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        for i in 1...5 {
            p.addLine(to: CGPoint(x: r.minX + r.width * CGFloat(i) / 5, y: i % 2 == 0 ? r.maxY : r.minY))
        }
        return p
    }
}

/// An ellipse drawn in one pass that overshoots and doesn't quite close.
struct LooseEllipse: Shape {
    var seed: Double = 2

    func path(in r: CGRect) -> Path {
        var p = Path()
        let steps = 48
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = -2.4 + t * 2 * .pi * 1.08
            let grow = 1 + 0.07 * t
            let rx = r.width / 2 * grow * (1 + 0.03 * CGFloat(sin(3 * a + seed)))
            let ry = r.height / 2 * grow * (1 + 0.03 * CGFloat(sin(2 * a + seed)))
            let pt = CGPoint(x: r.midX + rx * CGFloat(cos(a)), y: r.midY + ry * CGFloat(sin(a)))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
}

/// Square drawn with four strokes whose corners overshoot slightly.
struct DoodleBox: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let e: CGFloat = 1.2
        p.move(to: CGPoint(x: r.minX - e, y: r.minY + 0.5)); p.addLine(to: CGPoint(x: r.maxX + e, y: r.minY - 0.4))
        p.move(to: CGPoint(x: r.maxX + 0.4, y: r.minY - e)); p.addLine(to: CGPoint(x: r.maxX - 0.5, y: r.maxY + e))
        p.move(to: CGPoint(x: r.maxX + e, y: r.maxY - 0.4)); p.addLine(to: CGPoint(x: r.minX - e, y: r.maxY + 0.5))
        p.move(to: CGPoint(x: r.minX + 0.4, y: r.maxY + e)); p.addLine(to: CGPoint(x: r.minX - 0.3, y: r.minY - e))
        return p
    }
}

/// Check mark with a trailing flick.
struct Tick: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.55))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.4, y: r.maxY - r.height * 0.05))
        p.addLine(to: CGPoint(x: r.maxX + 1, y: r.minY - 2))
        return p
    }
}

/// Big ballpoint numeral with a faint ink-bleed copy.
struct Num: View {
    let text: String
    var color: Color = Ink.ballpoint
    var size: CGFloat = 24

    var body: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: text).opacity(0.25).offset(x: 0.4, y: 0.4)
            Text(verbatim: text)
        }
        .font(Ink.num(size))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }
}

/// One line of the notebook: content sits on a faint drawn rule.
struct RuledRow<C: View>: View {
    let height: CGFloat
    var seed: Double = 0
    @ViewBuilder let content: () -> C

    var body: some View {
        content()
            .padding(.bottom, 1.5)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .bottomLeading)
            .overlay(alignment: .bottom) {
                PencilLine(seed: seed).stroke(Ink.ruled, lineWidth: 0.8).frame(height: 1)
            }
    }
}

/// Small tactile press: scale to 0.94, quick ease-out.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Keyboard focus for the hand-drawn controls: Tab moves between them, Return or space activates, and the focused one gets a pencil box
/// (only once Tab was used, so mouse users never see it).
private struct PencilFocus: ViewModifier {
    let action: () -> Void

    /// Lives inside the focusable view, so `isFocused` reflects it.
    private struct Ring: View {
        @Environment(\.isFocused) private var focused
        @EnvironmentObject var model: AppModel

        var body: some View {
            Group {
                if focused && model.usingKeyboard {
                    DoodleBox().stroke(Ink.pencil.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .padding(-2).allowsHitTesting(false)
                }
            }
            .onChange(of: focused) { model.focusedControls += $1 ? 1 : -1 }
            .onDisappear { if focused { model.focusedControls -= 1 } } // the card went away with the focused control
        }
    }

    func body(content: Content) -> some View {
        content
            .focusable(false) // a Button is focusable by itself with Full Keyboard Access: one Tab stop per control, not two
            .overlay { Ring() }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
    }
}

extension View {
    func pencilFocus(_ action: @escaping () -> Void) -> some View { modifier(PencilFocus(action: action)) }
}

/// A − or + written in pencil; a scribble underlines it on hover.
struct PencilTap: View {
    let glyph: String
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            Text(verbatim: glyph).font(Ink.hand(13)).foregroundStyle(Ink.pencil)
                .frame(width: 13, height: 17)
                .overlay(alignment: .bottom) {
                    Scribble().trim(from: 0, to: hover.value ? 1 : 0)
                        .stroke(Ink.pencil.opacity(0.75), lineWidth: 0.9).frame(width: 9, height: 2.5).offset(y: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pencilFocus(action)
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.18), value: hover.value)
    }
}

/// A word on the page that can be tapped; its wavy underline is redrawn on hover.
struct WordLink: View {
    let title: LocalizedStringKey
    var size: CGFloat = 11
    var underlined = false
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            Text(title).font(Ink.hand(size)).foregroundStyle(Ink.pencil)
                .overlay(alignment: .bottom) {
                    if underlined || hover.value {
                        WavyLine().trim(from: 0, to: hover.value ? 1 : 0.72)
                            .stroke(Ink.pencil.opacity(0.85), lineWidth: 1.1).frame(height: 3).offset(y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pencilFocus(action)
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.25), value: hover.value)
    }
}

/// Doodled check box with a tick; used for yes / no and the preview option.
struct BoxChoice: View {
    let title: LocalizedStringKey
    var checked: Bool? = nil
    var size: CGFloat = 11
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                DoodleBox().stroke(Ink.pencil.opacity(0.9), lineWidth: 1).frame(width: 9, height: 9)
                    .overlay {
                        Tick().trim(from: 0, to: (checked ?? hover.value) ? 1 : 0)
                            .stroke(Ink.pencil, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 9, height: 9)
                    }
                Text(title).font(Ink.hand(size)).foregroundStyle(Ink.pencil)
            }
            .frame(minHeight: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pencilFocus(action)
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.2), value: hover.value)
        .animation(.easeOut(duration: 0.2), value: checked)
    }
}

/// Mint washi tape with torn ends and faint stripes.
struct WashiTape: View {
    var width: CGFloat = 54
    var height: CGFloat = 15

    private struct Torn: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            let teeth = 5
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            for i in 1...teeth { p.addLine(to: CGPoint(x: r.maxX - (i % 2 == 0 ? 0 : 1.8), y: r.minY + r.height * CGFloat(i) / CGFloat(teeth))) }
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            for i in (0..<teeth).reversed() { p.addLine(to: CGPoint(x: r.minX + (i % 2 == 0 ? 0 : 1.8), y: r.minY + r.height * CGFloat(i) / CGFloat(teeth))) }
            p.closeSubpath()
            return p
        }
    }

    var body: some View {
        Torn().fill(Ink.washi.opacity(0.9))
            .overlay {
                Canvas { ctx, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var l = Path()
                        l.move(to: CGPoint(x: x, y: size.height)); l.addLine(to: CGPoint(x: x + size.height, y: 0))
                        ctx.stroke(l, with: .color(.white.opacity(0.35)), lineWidth: 2)
                        x += 7
                    }
                }
                .clipShape(Torn())
            }
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.18), radius: 1.2, y: 1)
    }
}
