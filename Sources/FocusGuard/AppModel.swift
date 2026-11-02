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
    /// This session runs as a plain timer: the camera setting is off, or "not now" was chosen on the camera card.
    @Published var timerOnly = false
    /// Why launch at login could not be set, shown on the settings note.
    @Published var loginNote: String?
    /// Launch at login is registered but waits for the user's approval in System Settings.
    @Published var loginApproval = false
    /// True once Tab was used, so the pencil focus box shows only for keyboard navigation.
    @Published var usingKeyboard = false
    /// A pencil control has keyboard focus: space then belongs to it.
    var focusedControls = 0 { didSet { focusedControls = max(0, focusedControls) } } // onChange and onDisappear can both fire for one control
    var controlFocused: Bool { focusedControls > 0 }
    var panelOpen = false

    @Published var config: SessionConfig { didSet { save() } }
    @Published var sensitivity: Double { didSet { save(); scorer?.params = .forSensitivity(sensitivity) } }
    @Published var showPreview: Bool { didSet { save() } }
    @Published var useCamera: Bool {
        didSet {
            save()
            guard clock.phase.isRunning, useCamera == timerOnly else { return }
            timerOnly = !useCamera // the switch must take effect now: stop the camera, or start it for the running phase
            phaseChanged()
        }
    }
    @Published var soundsOn: Bool { didSet { save() } }
    @Published var musicOn: Bool { didSet { save() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLogin, launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginNote = nil
                loginApproval = SMAppService.mainApp.status == .requiresApproval
            } catch { // not running from an app bundle (swift run), or the user removed it in System Settings
                syncLogin()
                loginNote = String(localized: "only works from the installed app")
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
    /// Bumped whenever the camera is started or stopped, so a late start completion cannot overwrite a newer state.
    private var cameraGeneration = 0

    init() {
        let d = UserDefaults.standard
        config = SessionConfig(studyMinutes: d.object(forKey: "studyMinutes") as? Int ?? 25,
                               breakMinutes: d.object(forKey: "breakMinutes") as? Int ?? 5,
                               rounds: d.object(forKey: "rounds") as? Int ?? 4)
        sensitivity = d.object(forKey: "sensitivity") as? Double ?? 0.5
        showPreview = d.object(forKey: "showPreview") as? Bool ?? false
        useCamera = d.object(forKey: "useCamera") as? Bool ?? true
        soundsOn = d.object(forKey: "soundsOn") as? Bool ?? true
        musicOn = d.object(forKey: "musicOn") as? Bool ?? false
        seenHint = d.object(forKey: "seenHint") as? Bool ?? false
        cameraExplained = d.object(forKey: "cameraExplained") as? Bool ?? false
        launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)

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
    /// nil without camera data: no figure is better than a made-up one.
    var studiedMinutes: Int { clock.config.studyMinutes * clock.config.rounds }
    var averageFocus: Int? { history.isEmpty ? nil : Int(history.reduce(0, +) / Double(history.count)) }
    /// Focus figures need a running camera that has finished calibrating on a real face.
    var showsFocus: Bool { !timerOnly && camera == .running && !calibrating }
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
        if useCamera && !cameraExplained && AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
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

    /// "not now" on the camera card: the session still starts, as a plain timer.
    func startWithoutCamera() {
        showCameraWhy = false
        start(withCamera: false)
    }

    func start(withCamera: Bool = true) {
        timerOnly = !(withCamera && useCamera)
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

    func panelOpened() {
        panelOpen = true
        now = Date()
        usingKeyboard = false
        syncLogin()
    }

    /// Launch at login can change behind our back (System Settings), so read it again whenever the panel opens.
    private func syncLogin() {
        syncingLogin = true
        launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
        syncingLogin = false
        loginApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func panelClosed() {
        panelOpen = false
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
        let date = Date()
        if panelOpen || clock.phase.isRunning { now = date } // nothing on screen changes otherwise
        if clock.tick(at: date) {
            now = date
            phaseChanged()
            phaseStart = date
            if let announcement = before.announcement(to: clock.phase) { announce(announcement) }
        }
        guard clock.phase.isStudy, !clock.isPaused else { return }
        if showsFocus, now.timeIntervalSince(lastSample) >= 5 {
            history.append(focus)
            lastSample = now
        }
        // Camera unplugged or busy: retry every 5 s.
        if camera == .unavailable, !timerOnly, now.timeIntervalSince(lastCameraRetry) >= 5 {
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
        if !panelOpen { Bubble.show(text, cat: timeOfDay.art.catFace) } // the open panel's card already says it
    }

    /// Camera runs only while actively studying.
    private func phaseChanged() {
        now = Date()
        if clock.phase.isStudy && !clock.isPaused && !timerOnly {
            scorer = FocusScorer(params: .forSensitivity(sensitivity), start: now.timeIntervalSinceReferenceDate)
            focus = 100
            calibrating = true
            startCamera()
        } else {
            scorer = nil
            cameraGeneration += 1
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
        cameraGeneration += 1
        let generation = cameraGeneration
        cameraService.start { [weak self] status in
            guard let self, generation == self.cameraGeneration else { return }
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
        if !panelOpen { Bubble.show(Lines.random(for: event), cat: timeOfDay.art.catFace) } // the open panel shows the alert cat
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(config.studyMinutes, forKey: "studyMinutes")
        d.set(config.breakMinutes, forKey: "breakMinutes")
        d.set(config.rounds, forKey: "rounds")
        d.set(sensitivity, forKey: "sensitivity")
        d.set(showPreview, forKey: "showPreview")
        d.set(useCamera, forKey: "useCamera")
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
