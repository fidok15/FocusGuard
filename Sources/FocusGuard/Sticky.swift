import AppKit
import SwiftUI

/// Always-visible way out: menu bar apps have no Dock icon or app menu. Washi tape across the corner with a pencil ×. Also bound to ⌘Q.
struct QuitButton: View {
    @StateObject private var hover = Box(false)

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            ZStack {
                WashiTape(width: 52, height: 16)
                Path { p in
                    p.move(to: CGPoint(x: -3.5, y: -3)); p.addLine(to: CGPoint(x: 3.2, y: 3.6))
                    p.move(to: CGPoint(x: 3.5, y: -3.2)); p.addLine(to: CGPoint(x: -3.3, y: 3.4))
                }
                .stroke(Ink.pencil, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-45))
            }
            .contentShape(Rectangle())
            .rotationEffect(.degrees(45))
            .scaleEffect(hover.value ? 1.1 : 1)
            .brightness(hover.value ? 0.05 : 0)
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
            Text("Settings").font(Ink.hand(13))
                .overlay(alignment: .bottom) { WavyLine(seed: 3).stroke(Ink.pencil.opacity(0.8), lineWidth: 1).frame(height: 3).offset(y: 3) }
                .padding(.bottom, 4)
            Text("Alert sensitivity").font(Ink.hand(11))
            HandSlider(value: $model.sensitivity)
            HStack {
                Text("gentle")
                Spacer()
                Text("sensitive")
            }.font(Ink.hand(9))
            BoxChoice(title: "Camera preview", checked: model.showPreview) { model.showPreview.toggle() }
                .padding(.top, 4)
            WordLink(title: "close the app", size: 11, underlined: true) { NSApp.terminate(nil) }
        }
        .foregroundStyle(Ink.pencil)
        .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 14)
        .frame(width: 190, alignment: .leading)
        .background {
            CurledNote()
                .fill(LinearGradient(colors: [Ink.sticky.opacity(0.93), Ink.sticky], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 1, y: 3)
        }
        .overlay(alignment: .bottomTrailing) {
            Flap().fill(LinearGradient(colors: [Ink.sticky.opacity(0.7), Color(red: 0.8, green: 0.7, blue: 0.3)],
                                       startPoint: .topTrailing, endPoint: .bottomLeading))
                .frame(width: 14, height: 14).shadow(color: .black.opacity(0.25), radius: 1.5, x: -1, y: -1)
        }
        .overlay(alignment: .top) { WashiTape(width: 58, height: 14).rotationEffect(.degrees(-4)).offset(y: -7) }
        .rotationEffect(.degrees(-2))
    }
}
