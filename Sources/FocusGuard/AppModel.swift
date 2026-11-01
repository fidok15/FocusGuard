import AppKit
import AVFoundation
import FocusCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var clock = SessionClock()
    @Published var now = Date()
    @Published var focus = 100.0
    @Published var history: [Double] = []
    @Published var nudges = 0
    @Published var calibrating = false
    @Published var camera: CameraStatus = .off
    @Published var alerting = false
    @Published var showSetup = false
    @Published var showSettings = false
    @Published var confirmStop = false
    /// Explains the camera on the card before the system prompt shows (first session only).
    @Published var showCameraWhy = false
    /// Why the running clock is paused, so the card can say it.
    @Published var pausedBySleep = false
    /// When the current phase started; drives the clock's start flash.
    @Published var phaseStart = Date.distantPast

    @Published var config: SessionConfig { didSet { save() } }
    @Published var sensitivity: Double { didSet { save(); scorer?.params = .forSensitivity(sensitivity) } }
    @Published var showPreview: Bool { didSet { save() } }
    @Published var soundsOn: Bool { didSet { save() } }
    @Published var musicOn: Bool { didSet { save() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLogin, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch { // not running from an app bundle (swift run), or the user removed it in System Settings
                syncingLogin = true
                launchAtLogin = oldValue
                syncingLogin = false
            }
        }
    }
    /// The first-run hint stays on the card until the first session starts.
    @Published var seenHint: Bool { didSet { save() } }
    var cameraExplained: Bool { didSet { save() } }

    let cameraService = CameraService()
    /// Set by the panel controller: closes the panel (Esc).
    var closePanel: () -> Void = {}
    private var scorer: FocusScorer?
    private var lastSample = Date.distantPast
    private var lastCameraRetry = Date.distantPast
    private var activity: NSObjectProtocol?
    private var timer: Timer?
    private var alertReset: DispatchWorkItem?
    private var syncingLogin = false

    init() {
        let d = UserDefaults.standard
        config = SessionConfig(studyMinutes: d.object(forKey: "studyMinutes") as? Int ?? 25,
                               breakMinutes: d.object(forKey: "breakMinutes") as? Int ?? 5,
                               rounds: d.object(forKey: "rounds") as? Int ?? 4)
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.5
        showPreview = d.object(forKey: "showPreview") as? Bool ?? false
        soundsOn = d.object(forKey: "soundsOn") as? Bool ?? true
        musicOn = d.object(forKey: "musicOn") as? Bool ?? false
        seenHint = d.object(forKey: "seenHint") as? Bool ?? false
        cameraExplained = d.object(forKey: "cameraExplained") as? Bool ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled

        cameraService.onSignals = { [weak self] signals, t in
            Task { @MainActor in self?.handle(signals, at: t) }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Sleeping Mac, locked screen or sleeping display: pause instead of nudging an empty chair.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pauseBecauseAway() }
            }
        }
    }

    // MARK: Derived state

    var timeOfDay: TimeOfDay { timeOverride ?? TimeOfDay(date: now) }
    var timeOverride: TimeOfDay?
    /// Which card is showing above the clock; changing it plays the card's enter motion.
    var cardKey: String {
        if confirmStop { return "confirm" }
        switch clock.phase {
        case .study: return "study"
        case .rest: return "rest"
        case .idle, .done:
            if showCameraWhy { return "why" }
            if showSetup { return "setup" }
            if clock.phase == .done { return "done" }
            return seenHint ? "idle" : "hint"
        }
    }
    var remaining: TimeInterval { clock.remaining(at: now) }
    var remainingText: String {
        let s = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    var averageFocus: Int { history.isEmpty ? 0 : Int(history.reduce(0, +) / Double(history.count)) }
    var menuMood: MenuIcon.Mood {
        if alerting { return .alert }
        return clock.phase.isStudy && !clock.isPaused ? .studying : .idle
    }
    /// "25 min, 5 min break, 4 rounds"
    var summary: String {
        String(localized: "\(config.studyMinutes) min, \(config.breakMinutes) min break, \(config.rounds) rounds")
    }

    // MARK: Actions

    /// Click on the clock or space while idle: start with the last-used settings, after the one-time camera explanation.
    func requestStart() {
        showSettings = false
        showSetup = false
        if !cameraExplained && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            showCameraWhy = true
        } else {
            start()
        }
    }

    func confirmCameraWhy() {
        cameraExplained = true
        showCameraWhy = false
        start()
    }

    func start() {
        history = []
        nudges = 0
        showSetup = false
        showCameraWhy = false
        pausedBySleep = false
        seenHint = true
        phaseStart = Date()
        clock.start(config, at: Date())
        // Keeps App Nap from throttling the timer without blocking idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Study session timer")
        phaseChanged()
    }

    func stop() {
        clock.stop()
        confirmStop = false
        pausedBySleep = false
        phaseChanged()
    }

    func togglePause() {
        guard clock.phase.isRunning else { return }
        pausedBySleep = false
        if clock.isPaused { clock.resume(at: Date()) } else { clock.pause(at: Date()) }
        phaseChanged()
    }

    private func pauseBecauseAway() {
        guard clock.phase.isRunning, !clock.isPaused else { return }
        togglePause()
        pausedBySleep = true
    }

    func clockTapped() {
        showSettings = false
        showCameraWhy = false
        if clock.phase.isRunning { confirmStop.toggle() } else { requestStart() }
    }

    /// Space: start when idle, otherwise pause or resume.
    func spaceTapped() {
        confirmStop = false
        if clock.phase.isRunning { togglePause() } else { requestStart() }
    }

    func toggleSettings() {
        showSettings.toggle()
        showSetup = false
        confirmStop = false
    }

    func panelClosed() {
        showSettings = false
        showCameraWhy = false
        confirmStop = false
    }

    func openCameraSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    // MARK: Engine

    private func tick() {
        let before = clock.phase
        now = Date()
        if clock.tick(at: now) {
            phaseChanged()
            phaseStart = now
            if let announcement = before.announcement(to: clock.phase) { announce(announcement) }
        }
        guard clock.phase.isStudy, !clock.isPaused else { return }
        if !calibrating, now.timeIntervalSince(lastSample) >= 5 {
            history.append(focus)
            lastSample = now
        }
        // Camera unplugged or busy: retry every 5 s.
        if camera == .unavailable, now.timeIntervalSince(lastCameraRetry) >= 5 {
            lastCameraRetry = now
            startCamera()
        }
    }

    /// A subtle chime (if sounds are on) and a speech bubble from the cat.
    private func announce(_ a: Announcement) {
        let text: String, sound: String
        switch a {
        case .breakStarted: (text, sound) = (String(localized: "Break time, stretch a bit~"), "Glass")
        case .backToWork: (text, sound) = (String(localized: "Back to it, you've got this~"), "Pop")
        case .allDone: (text, sound) = (String(localized: "All done, nice work! ♡"), "Glass")
        }
        if soundsOn { NSSound(named: sound)?.play() }
        Bubble.show(text, cat: timeOfDay.art.catFace)
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
        alertReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in self?.alerting = false }
        alertReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: reset)
        Bubble.show(Lines.random(for: event), cat: timeOfDay.art.catFace)
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(config.studyMinutes, forKey: "studyMinutes")
        d.set(config.breakMinutes, forKey: "breakMinutes")
        d.set(config.rounds, forKey: "rounds")
        d.set(sensitivity, forKey: "sensitivity")
        d.set(showPreview, forKey: "showPreview")
        d.set(soundsOn, forKey: "soundsOn")
        d.set(musicOn, forKey: "musicOn")
        d.set(seenHint, forKey: "seenHint")
        d.set(cameraExplained, forKey: "cameraExplained")
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
