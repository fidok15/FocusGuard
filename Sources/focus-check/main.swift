import Foundation
@testable import FocusCore

private var failures = 0
private var current = ""
private func check(_ ok: Bool, line: Int = #line) {
    if !ok { failures += 1; print("  FAIL \(current) (line \(line))") }
}

private let fps = 10.0
private let look = FaceSignals(faceFound: true, ear: 0.3, gazeOffset: 0.1, yaw: 0, pitch: 0, confidence: 0.9)
private var away: FaceSignals { var s = look; s.yaw = 45; return s }
private var closed: FaceSignals { var s = look; s.ear = 0.1; return s }

/// Feeds `signal(t)` at 10 fps from 0 to `until` seconds and collects events.
private func run(_ params: ScorerParams = .standard, until: Double, _ signal: (Double) -> FaceSignals) -> [FocusEvent] {
    let scorer = FocusScorer(params: params, start: 0)
    var events: [FocusEvent] = []
    for i in 0...Int(until * fps) {
        let t = Double(i) / fps
        if let e = scorer.process(signal(t), at: t) { events.append(e) }
    }
    return events
}

/// Focused, except `away` between `from` and `from + length`.
private func distraction(from: Double, length: Double) -> (Double) -> FaceSignals {
    { t in (from..<(from + length)).contains(t) ? away : look }
}

func oneSecondDipNeverAlerts() {
    check(run(until: 200, distraction(from: 100, length: 1)).isEmpty)
}

func twentySecondDistractionDoesNotAlert() {
    check(run(until: 200, distraction(from: 100, length: 20)).isEmpty)
}

func thirtySecondDistractionAlertsOnce() {
    check(run(until: 200, distraction(from: 100, length: 30)) == [.lowFocus])
}

func longDistractionRepeatsOnlyAfterCooldown() {
    // Alerts at ~125, 305, 485, 665 s with a 180 s cooldown.
    check(run(until: 720, distraction(from: 100, length: 600)) == Array(repeating: .lowFocus, count: 4))
}

func noAlertDuringGracePeriod() {
    check(run(until: 59, distraction(from: 12, length: 47)).isEmpty)
}

func blinksAreNotDistraction() {
    let scorer = FocusScorer(params: .standard, start: 0)
    for i in 0...3000 {
        let t = Double(i) / fps
        // 0.3 s blink every 3 s
        let s = t > 15 && t.truncatingRemainder(dividingBy: 3) < 0.3 ? closed : look
        check(scorer.process(s, at: t) == nil)
    }
    check(scorer.score == 100)
}

func longEyeClosureIsDistraction() {
    check(run(until: 200, { t in (100..<130).contains(t) ? closed : look }) == [.lowFocus])
}

func absenceAlertsExactlyOnce() {
    check(run(until: 300, { t in (100..<200).contains(t) ? .noFace : look }) == [.absent])
}

func sensitivityInterpolatesPresets() {
    check(ScorerParams.forSensitivity(0) == .gentle)
    check(ScorerParams.forSensitivity(0.5) == .standard)
    check(ScorerParams.forSensitivity(1) == .sensitive)
    check(ScorerParams.forSensitivity(0.25).threshold == 45)
}

func sessionRunsStudyBreakCyclesToDone() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 2), at: t0)
    check(clock.phase == .study(round: 1))
    clock.tick(at: t0 + 25 * 60)
    check(clock.phase == .rest(round: 1))
    clock.tick(at: t0 + 30 * 60)
    check(clock.phase == .study(round: 2))
    clock.tick(at: t0 + 55 * 60)
    check(clock.phase == .done)
}

func sessionSkipsPhasesMissedDuringSleep() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 4), at: t0)
    let changed = clock.tick(at: t0 + 61 * 60)
    check(changed)
    check(clock.phase == .study(round: 3))
    check(clock.remaining(at: t0 + 61 * 60) == 24 * 60)
}

func pauseFreezesRemainingTime() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 1), at: t0)
    clock.pause(at: t0 + 600)
    let changed = clock.tick(at: t0 + 3600)
    check(!changed)
    check(clock.remaining(at: t0 + 3600) == 900)
    clock.resume(at: t0 + 3600)
    clock.tick(at: t0 + 3600 + 900)
    check(clock.phase == .done)
}

let checks: [(String, () -> Void)] = [
    ("oneSecondDipNeverAlerts", oneSecondDipNeverAlerts),
    ("twentySecondDistractionDoesNotAlert", twentySecondDistractionDoesNotAlert),
    ("thirtySecondDistractionAlertsOnce", thirtySecondDistractionAlertsOnce),
    ("longDistractionRepeatsOnlyAfterCooldown", longDistractionRepeatsOnlyAfterCooldown),
    ("noAlertDuringGracePeriod", noAlertDuringGracePeriod),
    ("blinksAreNotDistraction", blinksAreNotDistraction),
    ("longEyeClosureIsDistraction", longEyeClosureIsDistraction),
    ("absenceAlertsExactlyOnce", absenceAlertsExactlyOnce),
    ("sensitivityInterpolatesPresets", sensitivityInterpolatesPresets),
    ("sessionRunsStudyBreakCyclesToDone", sessionRunsStudyBreakCyclesToDone),
    ("sessionSkipsPhasesMissedDuringSleep", sessionSkipsPhasesMissedDuringSleep),
    ("pauseFreezesRemainingTime", pauseFreezesRemainingTime),
]
for (name, body) in checks {
    current = name
    let before = failures
    body()
    print(failures == before ? "ok   \(name)" : "FAIL \(name)")
}
print(failures == 0 ? "All \(checks.count) checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
