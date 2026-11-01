import AppKit
import SwiftUI

/// Always-visible way out: menu bar apps have no Dock icon or app menu. Washi tape across the corner with a pencil ×. Also bound to ⌘Q.
struct QuitButton: View {
    @StateObject private var hover = Box(false)

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            ZStack {
                WashiTape(width: 64, height: 20)
                Path { p in
                    p.move(to: CGPoint(x: -4.5, y: -4)); p.addLine(to: CGPoint(x: 4.2, y: 4.6))
                    p.move(to: CGPoint(x: 4.6, y: -4.2)); p.addLine(to: CGPoint(x: -4.3, y: 4.4))
                }
                .stroke(Ink.pencil, style: StrokeStyle(lineWidth: hover.value ? 2.2 : 1.8, lineCap: .round))
                .rotationEffect(.degrees(-45))
            }
            .contentShape(Rectangle())
            .rotationEffect(.degrees(45))
            .scaleEffect(hover.value ? 1.1 : 1)
            .brightness(hover.value ? 0.06 : 0)
            .shadow(color: .black.opacity(hover.value ? 0.35 : 0.2), radius: hover.value ? 3 : 1.5, y: 1)
        }
        .buttonStyle(PressStyle())
        .keyboardShortcut("q")
        .onHover { hover.value = $0 }
        .help("Quit FocusGuard")
        .animation(.easeOut(duration: 0.15), value: hover.value)
    }
}

/// Square sticky note with a curled bottom-right corner.
private struct CurledNote: Shape {
    var curl: CGFloat = 14

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - curl))
        p.addLine(to: CGPoint(x: r.maxX - curl, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Flap: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.closeSubpath()
        return p
    }
}

/// A line you drag a graphite dot along; the stretch behind the dot is gone over twice.
private struct HandSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                PencilLine(seed: 5, amp: 0.8).stroke(Ink.pencil.opacity(0.55), lineWidth: 1.2).frame(height: 3)
                PencilLine(seed: 6, amp: 0.8).trim(from: 0, to: value).stroke(Ink.pencil, lineWidth: 2).frame(height: 3)
                Circle().fill(Ink.pencil).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Ink.pencil.opacity(0.4), lineWidth: 1).padding(-3))
                    .offset(x: (w - 11) * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                value = min(max(Double((v.location.x - 5.5) / (w - 11)), 0), 1)
            })
        }
        .frame(height: 18)
    }
}

struct SettingsNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings").font(Ink.hand(13))
                .overlay(alignment: .bottom) { WavyLine(seed: 3).stroke(Ink.pencil.opacity(0.8), lineWidth: 1).frame(height: 3).offset(y: 3) }
                .padding(.bottom, 4)
            Text("alert sensitivity").font(Ink.hand(11))
            HandSlider(value: $model.sensitivity)
            HStack {
                Text("gentle")
                Spacer()
                Text("sensitive")
            }.font(Ink.hand(11))
            VStack(alignment: .leading, spacing: 1) {
                BoxChoice(title: "camera preview", checked: model.showPreview) { model.showPreview.toggle() }
                BoxChoice(title: "sounds", checked: model.soundsOn) { model.soundsOn.toggle() }
                BoxChoice(title: "launch at login", checked: model.launchAtLogin) { model.launchAtLogin.toggle() }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Ink.pencil)
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(width: 190, alignment: .leading)
        .background {
            CurledNote()
                .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.91, blue: 0.52), Ink.sticky], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 1, y: 3)
        }
        .overlay(alignment: .bottomTrailing) {
            Flap().fill(LinearGradient(colors: [Color(red: 0.9, green: 0.82, blue: 0.4), Color(red: 0.8, green: 0.7, blue: 0.3)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: 14, height: 14).shadow(color: .black.opacity(0.25), radius: 1.5, x: -1, y: -1)
        }
        .overlay(alignment: .top) { WashiTape(width: 58, height: 14).rotationEffect(.degrees(-4)).offset(y: -7) }
        .rotationEffect(.degrees(-2))
    }
}
