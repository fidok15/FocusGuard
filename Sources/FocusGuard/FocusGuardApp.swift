import AppKit
import FocusCore
import SwiftUI

@main
struct FocusGuardApp: App {
    @StateObject private var model = AppModel()

    init() {
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            Snapshots.render(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            DeskScene().environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(nsImage: MenuIcon.image(model.menuMood))
                if model.clock.phase.isRunning { Text(verbatim: model.remainingText).monospacedDigit() }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published fileprivate(set) var clock = SessionClock()
    @Published fileprivate(set) var now = Date()
    @Published fileprivate(set) var focus = 100.0
    @Published fileprivate(set) var history: [Double] = []
    @Published fileprivate(set) var nudges = 0
    @Published fileprivate(set) var calibrating = false
    @Published fileprivate(set) var camera: CameraStatus = .off
    @Published fileprivate(set) var alerting = false
    @Published var showSetup = false
    @Published var showSettings = false
    @Published var confirmStop = false

    @Published var config: SessionConfig { didSet { save() } }
    @Published var sensitivity: Double { didSet { save(); scorer?.params = .forSensitivity(sensitivity) } }
    @Published var showPreview: Bool { didSet { save() } }

    let cameraService = CameraService()
    private var scorer: FocusScorer?
    private var lastSample = Date.distantPast
    private var lastCameraRetry = Date.distantPast
    private var activity: NSObjectProtocol?
    private var timer: Timer?

    init() {
        let d = UserDefaults.standard
        config = SessionConfig(studyMinutes: d.object(forKey: "studyMinutes") as? Int ?? 25,
                               breakMinutes: d.object(forKey: "breakMinutes") as? Int ?? 5,
                               rounds: d.object(forKey: "rounds") as? Int ?? 4)
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.5
        showPreview = d.object(forKey: "showPreview") as? Bool ?? false

        cameraService.onSignals = { [weak self] signals, t in
            Task { @MainActor in self?.handle(signals, at: t) }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Derived state

    var timeOfDay: TimeOfDay { timeOverride ?? TimeOfDay(date: now) }
    var timeOverride: TimeOfDay?
    var remaining: TimeInterval { clock.remaining(at: now) }
    var remainingText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    var remainingFraction: Double { clock.phaseDuration > 0 ? remaining / clock.phaseDuration : 0 }
    var averageFocus: Int { history.isEmpty ? 0 : Int(history.reduce(0, +) / Double(history.count)) }
    var menuMood: MenuIcon.Mood {
        if alerting { return .alert }
        return clock.phase.isStudy && !clock.isPaused ? .studying : .sleeping
    }

    // MARK: Actions

    func start() {
        history = []
        nudges = 0
        showSetup = false
        clock.start(config, at: Date())
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Study session timer")
        phaseChanged()
    }

    func stop() {
        clock.stop()
        confirmStop = false
        phaseChanged()
    }

    func togglePause() {
        guard clock.phase.isRunning else { return }
        if clock.isPaused { clock.resume(at: Date()) } else { clock.pause(at: Date()) }
        phaseChanged()
    }

    func timerTapped() {
        showSettings = false
        if clock.phase.isRunning { confirmStop.toggle() } else { showSetup.toggle() }
    }

    func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    // MARK: Engine

    private func tick() {
        now = Date()
        if clock.tick(at: now) { phaseChanged() }
        guard clock.phase.isStudy, !clock.isPaused else { return }
        if now.timeIntervalSince(lastSample) >= 5 {
            history.append(focus)
            lastSample = now
        }
        // Camera unplugged or busy: retry every 5 s.
        if camera != .denied, !cameraService.isRunning, now.timeIntervalSince(lastCameraRetry) >= 5 {
            lastCameraRetry = now
            startCamera()
        }
    }

    /// Camera runs only while actively studying.
    private func phaseChanged() {
        now = Date()
        if clock.phase.isStudy && !clock.isPaused {
            scorer = FocusScorer(params: .forSensitivity(sensitivity), start: now.timeIntervalSinceReferenceDate)
            focus = 100
            calibrating = true
            startCamera()
        } else {
            scorer = nil
            cameraService.stop()
            camera = .off
            calibrating = false
        }
        if !clock.phase.isRunning, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func startCamera() {
        camera = .starting
        cameraService.start { [weak self] status in
            guard let self else { return }
            // The phase may have ended while the camera was starting.
            if self.scorer == nil { self.cameraService.stop(); self.camera = .off } else { self.camera = status }
        }
    }

    private func handle(_ signals: FaceSignals, at t: Double) {
        guard let scorer else { return }
        let event = scorer.process(signals, at: t)
        focus = scorer.smoothedScore
        calibrating = scorer.isCalibrating
        guard let event else { return }
        nudges += 1
        alerting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.alerting = false }
        Bubble.show(Lines.random(for: event), cat: timeOfDay.art.catFace)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(config.studyMinutes, forKey: "studyMinutes")
        d.set(config.breakMinutes, forKey: "breakMinutes")
        d.set(config.rounds, forKey: "rounds")
        d.set(sensitivity, forKey: "sensitivity")
        d.set(showPreview, forKey: "showPreview")
    }
}

enum Lines {
    static func random(for event: FocusEvent) -> String {
        switch event {
        case .absent:
            return [String(localized: "Where did you go? The cat is waiting~"),
                    String(localized: "Hello? Your notebook misses you!")].randomElement()!
        case .lowFocus:
            return [String(localized: "Hey! Your focus is slipping~"),
                    String(localized: "Psst… eyes back on the notebook!"),
                    String(localized: "The cat believes in you. Focus up! ♡"),
                    String(localized: "Deep breath, one more page~")].randomElement()!
        }
    }
}

#if DEBUG
/// `swift run FocusGuard --snapshots <dir>` renders the scene in key states to PNGs (README screenshots, visual checks).
@MainActor
enum Snapshots {
    static func render(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let model = AppModel()
        let t0 = Date()
        func shot(_ name: String, _ tod: TimeOfDay) {
            model.timeOverride = tod
            let renderer = ImageRenderer(content: DeskScene().environmentObject(model))
            renderer.scale = 2
            guard let cg = renderer.cgImage else { return print("failed \(name)") }
            let rep = NSBitmapImageRep(cgImage: cg)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("wrote \(name)")
        }
        shot("1-idle-morning", .morning)
        model.showSetup = true
        shot("2-setup-day", .day)
        model.start()
        model.cameraService.stop()
        model.camera = .running
        model.history = [92, 88, 85, 70, 55, 62, 78, 84, 90, 87]
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

        if let face = TimeOfDay.morning.art.catFace, let tiff = face.tiffRepresentation {
            try? NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/9-face.png"))
        }
        let bubble = ImageRenderer(content: BubbleView(text: Lines.random(for: .lowFocus), cat: TimeOfDay.morning.art.catFace) {}
            .frame(width: 300, height: 104).background(Color.gray.opacity(0.3)))
        bubble.scale = 2
        if let cg = bubble.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/7-bubble.png"))
        }
        let icons = ImageRenderer(content: HStack(spacing: 14) {
            ForEach([MenuIcon.Mood.sleeping, .studying, .alert], id: \.self) { mood in
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
