#if DEBUG
import AppKit
import SwiftUI

/// `swift run FocusGuard --window [morning|day|sunset|night] [--state ...] [--hover ...] [--autopet]` shows the scene in a
/// plain window, `--open-panel` opens the real transparent panel under a status item; both print the window number so
/// `screencapture -l` can record them. Both stay behind the user's windows, take no focus and show no Dock icon.
@MainActor
enum DebugWindow {
    static var window: NSWindow?

    /// States: idle (default), hint, setup, why, study, paused, sleep, settings, break, confirm, done, bubble, music, nudge.
    static func configure(_ model: AppModel) {
        model.persists = false // fixtures never touch the user's settings
        let args = CommandLine.arguments
        model.timeOverride = TimeOfDay.allCases.first { args.contains("\($0)") }
        let state = args.firstIndex(of: "--state").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "idle"
        let t0 = Date()
        model.seenHint = state != "hint"
        model.cameraExplained = true
        model.soundsOn = false
        model.musicOn = state == "music"
        model.showPreview = false
        if state == "setup" { model.showSetup = true }
        if state == "why" { model.cameraExplained = false; model.showCameraWhy = true }
        if ["study", "paused", "sleep", "settings", "break", "done", "confirm", "nudge"].contains(state) {
            model.start(withCamera: false) // no capture and no permission prompt; the card is told the camera runs
            model.timerOnly = false
            model.camera = .running
            model.lastSignal = .distantFuture; model.lastScored = .distantFuture // keep the camera watchdog quiet
            model.history = [94, 90, 84, 66, 48, 58, 76, 88, 72, 52, 64, 82, 91, 86]
            model.focus = 82
            model.calibrating = false
            model.now = t0.addingTimeInterval(7 * 60)
        }
        if state == "paused" || state == "sleep" { model.togglePause(); model.pausedBySleep = state == "sleep" }
        if state == "settings" { model.showSettings = true }
        if state == "confirm" { model.confirmStop = true }
        if state == "nudge" { model.nudgeText = Lines.random(for: .lowFocus) }
        if state == "break" { model.clock.tick(at: t0.addingTimeInterval(25 * 60 + 1)); model.now = t0.addingTimeInterval(27 * 60) }
        if state == "done" { model.clock.tick(at: t0.addingTimeInterval(24 * 3600)); model.nudges = 2 }
        if state == "bubble" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Bubble.show(Lines.random(for: .lowFocus), cat: model.timeOfDay.art.catFace)
            }
        }
    }

    static func show() {
        let model = AppModel()
        configure(model)
        let size = NSSize(width: CW + 2 * PAD, height: CH + 2 * PAD)
        let w = NSWindow(contentRect: NSRect(origin: CGPoint(x: 200, y: 200), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.contentView = NSHostingView(rootView: PanelRoot().environmentObject(model))
        // Stay behind the user's windows and never take focus; screencapture -l still records it.
        w.orderBack(nil)
        window = w
        print("window \(w.windowNumber)")
        fflush(stdout)
    }

    /// The real status item and panel, opened quietly.
    static func openPanel() -> PanelController {
        let model = AppModel()
        configure(model)
        let controller = PanelController(model: model, quiet: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            controller.show()
            print("window \(controller.windowNumber) \(controller.panel.frame)")
            fflush(stdout)
        }
        return controller
    }
}

/// `swift run FocusGuard --snapshots <dir>` renders the scene in key states to PNGs (README screenshots, visual checks).
@MainActor
enum Snapshots {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = AppModel()
        model.persists = false
        model.seenHint = true
        let t0 = Date()
        func shot(_ name: String, _ tod: TimeOfDay) {
            model.timeOverride = tod
            let renderer = ImageRenderer(content: PanelRoot().environmentObject(model))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))) != nil
            else { return print("failed \(name)") }
            print("wrote \(name)")
        }
        shot("1-idle-morning", .morning)
        model.showSetup = true
        shot("2-setup-day", .day)
        model.start(withCamera: false)
        model.timerOnly = false
        model.camera = .running
        model.history = [94, 90, 84, 66, 48, 58, 76, 88, 72, 52, 64, 82, 91, 86]
        model.focus = 82
        model.calibrating = false
        model.now = t0.addingTimeInterval(7 * 60)
        shot("3-study-sunset", .sunset)
        model.showSettings = true
        shot("4-settings-night", .night)
        model.showSettings = false
        model.clock.tick(at: t0.addingTimeInterval(25 * 60 + 1))
        model.now = t0.addingTimeInterval(27 * 60)
        shot("5-break-day", .day)
        model.clock.tick(at: t0.addingTimeInterval(24 * 3600))
        model.nudges = 2
        shot("6-done-night", .night)

        for tod in TimeOfDay.allCases {
            if let face = tod.art.catFace, let tiff = face.tiffRepresentation {
                try? NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/9-face-\(tod).png"))
            }
        }
        let bubble = ImageRenderer(content: BubbleView(text: Lines.random(for: .lowFocus), cat: TimeOfDay.morning.art.catFace) {}
            .frame(width: 300, height: 104).background(Color.gray.opacity(0.3)))
        bubble.scale = 2
        if let cg = bubble.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/7-bubble.png"))
        }
        let icons = ImageRenderer(content: HStack(spacing: 14) {
            ForEach([MenuIcon.Mood.idle, .studying, .alert], id: \.self) { mood in
                Image(nsImage: MenuIcon.image(mood)).renderingMode(.template).foregroundStyle(.black)
            }
        }.padding(8).background(Color.white))
        icons.scale = 6
        if let cg = icons.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/8-menu-icons.png"))
        }
    }
}
#endif
