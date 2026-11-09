import AppKit
import ServiceManagement
import SwiftUI

/// Washi tape across the corner with a pencil ×: hides the panel (⌘W too). Quitting lives in the menu bar icon's right-click menu and ⌘Q.
struct CloseButton: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TapeX(width: 64, height: 20, help: "Close", action: model.closePanel)
    }
}

/// A strip of washi tape stuck across a corner, with a pencil × on it.
struct TapeX: View {
    let width: CGFloat
    let height: CGFloat
    let help: LocalizedStringKey
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        let x = height / 2 // the × scales with the tape
        Button(action: action) {
            ZStack {
                WashiTape(width: width, height: height)
                Path { p in
                    p.move(to: CGPoint(x: 0.05 * x, y: 0.1 * x)); p.addLine(to: CGPoint(x: 0.92 * x, y: 0.96 * x))
                    p.move(to: CGPoint(x: 0.96 * x, y: 0.08 * x)); p.addLine(to: CGPoint(x: 0.07 * x, y: 0.94 * x))
                }
                .stroke(Ink.pencil, style: StrokeStyle(lineWidth: hover.value ? 2.2 : 1.8, lineCap: .round))
                .frame(width: x, height: x)
                .rotationEffect(.degrees(-45))
            }
            .contentShape(Rectangle())
            .rotationEffect(.degrees(45))
            .scaleEffect(hover.value ? 1.1 : 1)
            .brightness(hover.value ? 0.06 : 0)
            .shadow(color: .black.opacity(hover.value ? 0.35 : 0.2), radius: hover.value ? 3 : 1.5, y: 1)
        }
        .buttonStyle(PressStyle())
        .onHover { hover.value = $0 }
        .help(help)
        .accessibilityLabel(Text(help))
        .animation(.easeOut(duration: 0.15), value: hover.value)
    }
}

/// A × written in pencil and loosely circled, for closing a note from inside it.
struct PencilX: View {
    let help: LocalizedStringKey
    let action: () -> Void
    @StateObject private var hover = Box(false)

    var body: some View {
        Button(action: action) {
            Path { p in
                p.move(to: CGPoint(x: 0.5, y: 0.8)); p.addLine(to: CGPoint(x: 7.4, y: 7.8))
                p.move(to: CGPoint(x: 7.7, y: 0.6)); p.addLine(to: CGPoint(x: 0.6, y: 7.5))
            }
            .stroke(Ink.pencil, style: StrokeStyle(lineWidth: hover.value ? 1.8 : 1.4, lineCap: .round))
            .frame(width: 8, height: 8)
            .padding(6)
            .overlay { LooseEllipse(seed: 7).trim(from: 0, to: hover.value ? 1 : 0.82).stroke(Ink.pencil.opacity(0.7), lineWidth: 0.9) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .pencilFocus(action)
        .onHover { hover.value = $0 }
        .animation(.easeOut(duration: 0.18), value: hover.value)
        .help(help)
        .accessibilityLabel(Text(help))
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
        // Arrow keys and VoiceOver adjust it in tenths, like a native slider.
        .pencilFocus {} // Tab stop with the same pencil box as the other controls
        .onKeyPress(.leftArrow) { step(-0.1); return .handled }
        .onKeyPress(.rightArrow) { step(0.1); return .handled }
        .accessibilityElement()
        .accessibilityLabel(Text("alert sensitivity"))
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded())) %"))
        .accessibilityAdjustableAction { $0 == .increment ? step(0.1) : step(-0.1) }
    }

    private func step(_ by: Double) {
        value = min(max(((value + by) * 10).rounded() / 10, 0), 1)
    }
}

struct SettingsNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text("settings").font(Ink.hand(13))
                    .overlay(alignment: .bottom) { WavyLine(seed: 3).stroke(Ink.pencil.opacity(0.8), lineWidth: 1).frame(height: 3).offset(y: 3) }
                Spacer(minLength: 4)
                PencilX(help: "Close settings") { model.showSettings = false }.offset(x: 4, y: -4)
            }
            .padding(.bottom, 4)
            Text("alert sensitivity").font(Ink.hand(12))
            HandSlider(value: $model.sensitivity)
            HStack {
                Text("gentle")
                Spacer()
                Text("sensitive")
            }.font(Ink.hand(12))
            VStack(alignment: .leading, spacing: 1) {
                BoxChoice(title: "use camera", checked: model.useCamera, size: 12) { model.useCamera.toggle() }
                if model.useCamera {
                    BoxChoice(title: "camera preview", checked: model.showPreview, size: 12) { model.showPreview.toggle() }
                }
                BoxChoice(title: "sounds", checked: model.soundsOn, size: 12) { model.soundsOn.toggle() }
                BoxChoice(title: "bigger panel", checked: model.largePanel, size: 12) { model.largePanel.toggle() }
                BoxChoice(title: "launch at login", checked: model.launchAtLogin, size: 12) { model.launchAtLogin.toggle() }
                if model.loginApproval {
                    Button(action: SMAppService.openSystemSettingsLoginItems) {
                        Text("allow it in System Settings, Login Items").font(Ink.hand(11)).foregroundStyle(Ink.red)
                            .underline().fixedSize(horizontal: false, vertical: true)
                    }.buttonStyle(.plain)
                } else if let note = model.loginNote {
                    Text(note).font(Ink.hand(11)).foregroundStyle(Ink.red).fixedSize(horizontal: false, vertical: true)
                }
                if model.hotKeyTaken {
                    Text("⌃⌥⌘F is used by another app").font(Ink.hand(11)).foregroundStyle(Ink.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
        .foregroundStyle(Ink.pencil)
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(width: 196, alignment: .leading)
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

/// A kraft-paper record sleeve over the player: what Spotify plays, its cover, and pencil-drawn controls.
struct MusicNote: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let spotify = model.spotify
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Cover(image: spotify.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(spotify.playing ? "now playing" : "Spotify").font(Ink.hand(11)).opacity(0.7)
                    if let track = spotify.track {
                        Text(verbatim: track.title).font(Ink.hand(14)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: track.artist).font(Ink.hand(12)).opacity(0.8).lineLimit(1)
                    } else if spotify.running {
                        Text("nothing playing").font(Ink.hand(13))
                    } else {
                        Text("Spotify isn't open").font(Ink.hand(13))
                        WordLink(title: "open Spotify", size: 12, underlined: true, action: spotify.openSpotify).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if spotify.running {
                HStack(spacing: 0) {
                    PlayerKey(symbol: "shuffle", label: "shuffle", on: spotify.track?.shuffling) { spotify.send(.shuffle) }
                    Spacer(minLength: 0)
                    PlayerKey(symbol: "backward.fill", label: "previous") { spotify.send(.previous) }
                    Spacer(minLength: 0)
                    PlayerKey(symbol: spotify.playing ? "pause.fill" : "play.fill", label: spotify.playing ? "pause" : "play", big: true) {
                        spotify.send(.playPause)
                    }
                    Spacer(minLength: 0)
                    PlayerKey(symbol: "forward.fill", label: "next") { spotify.send(.next) }
                    Spacer(minLength: 0)
                    PlayerKey(symbol: "repeat", label: "repeat", on: spotify.track?.repeating) { spotify.send(.repeat) }
                }
                .padding(.horizontal, 2)
            }
            if spotify.access == .denied {
                Button(action: spotify.openAutomationSettings) {
                    Text("allow FocusGuard to control Spotify in System Settings").font(Ink.hand(11)).foregroundStyle(Ink.red)
                        .underline().fixedSize(horizontal: false, vertical: true)
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(Ink.pencil)
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .frame(width: 222, alignment: .leading)
        .background {
            CurledNote()
                .fill(LinearGradient(colors: [Color(red: 0.94, green: 0.88, blue: 0.77), Color(red: 0.89, green: 0.81, blue: 0.68)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.3), radius: 5, x: 1, y: 3)
        }
        .overlay(alignment: .topTrailing) {
            TapeX(width: 44, height: 15, help: "Close") { model.showMusic = false }.offset(x: 12, y: -5)
        }
        .rotationEffect(.degrees(1.5))
    }

    /// The album cover as a small print with a white border; a pencil record when there is none.
    private struct Cover: View {
        let image: NSImage?

        var body: some View {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().stroke(Ink.pencil.opacity(0.7), lineWidth: 1.2)
                        Circle().stroke(Ink.pencil.opacity(0.35), lineWidth: 0.8).padding(9)
                        Circle().fill(Ink.red.opacity(0.7)).frame(width: 14, height: 14)
                    }
                    .padding(6)
                }
            }
            .frame(width: 60, height: 60)
            .clipped()
            .padding(3)
            .background(Color.white.shadow(.drop(color: .black.opacity(0.3), radius: 2, y: 1)))
            .rotationEffect(.degrees(-3))
            .accessibilityHidden(true)
        }
    }

    /// One player control drawn in pencil; shuffle and repeat show whether they are on.
    private struct PlayerKey: View {
        let symbol: String
        let label: LocalizedStringKey
        var on: Bool? = nil
        var big = false
        let action: () -> Void
        @StateObject private var hover = Box(false)

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: big ? 17 : 12, weight: .bold))
                    .foregroundStyle(Ink.pencil.opacity(on == false ? 0.4 : 1))
                    .frame(width: big ? 34 : 24, height: big ? 30 : 24)
                    .overlay { if big { LooseEllipse(seed: 4).stroke(Ink.pencil.opacity(0.75), lineWidth: 1) } }
                    .overlay(alignment: .bottom) {
                        if on == true { Circle().fill(Ink.pencil).frame(width: 3, height: 3).offset(y: 1) }
                    }
                    .scaleEffect(hover.value ? 1.12 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .pencilFocus(action)
            .onHover { hover.value = $0 }
            .animation(.easeOut(duration: 0.15), value: hover.value)
            .help(label)
            .accessibilityLabel(Text(label))
            .accessibilityValue(on.map { $0 ? Text("on") : Text("off") } ?? Text(verbatim: ""))
        }
    }
}
