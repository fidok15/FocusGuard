import Foundation
@testable import FocusCore

private var failures = 0
private var current = ""
private func check(_ ok: Bool, line: Int = #line) {
    if !ok { failures += 1; print("  FAIL \(current) (line \(line))") }
}

private let fps = 10.0
private let look = FaceSignals(faceFound: true, ear: 0.3, gazeOffset: 0.1, yaw: 0, pitch: 0, confidence: 0.9)
/// Head well down, like reading a phone in your lap: never learned as a screen, so it always counts as away.
private var away: FaceSignals { var s = look; s.pitch = 45; return s }
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

/// Looking at a laptop 40° to the side: away at first, then a learned work zone.
private var laptop: FaceSignals { var s = look; s.yaw = 40; s.pitch = 12; return s }

/// Feeds `signal` from `from` to `to` seconds at 10 fps.
private func feed(_ scorer: FocusScorer, from: Double, to: Double, _ signal: FaceSignals) {
    for i in 0..<Int((to - from) * fps) { scorer.process(signal, at: from + Double(i) / fps) }
}

func secondScreenBecomesAZone() {
    let scorer = FocusScorer(params: .standard, start: 0)
    feed(scorer, from: 0, to: 100, look)
    check(scorer.classify(laptop, at: 100) == .lookingAway) // not learned yet
    feed(scorer, from: 100, to: 300, laptop)
    check(scorer.classify(laptop, at: 300) == .focused)
    check(scorer.score == 100)
    check(scorer.classify(away, at: 300) == .lookingAway) // the phone still counts as away
}

func zonesCarryOverToTheNextPhase() {
    let zones = PoseZones()
    let first = FocusScorer(params: .standard, start: 0, zones: zones)
    feed(first, from: 0, to: 20, look)
    feed(first, from: 20, to: 120, laptop)
    let next = FocusScorer(params: .standard, start: 200, zones: zones)
    feed(next, from: 200, to: 215, look) // calibration of the new phase
    check(next.classify(laptop, at: 215) == .focused)
}

func gazeIsRelativeToCalibration() {
    // A camera beside the screen sees the eye at an angle: the pupil sits off-centre even when you look straight ahead.
    var side = look; side.gazeOffset = 0.4
    let scorer = FocusScorer(params: .standard, start: 0)
    feed(scorer, from: 0, to: 15, side)
    var straight = side; straight.gazeOffset = 0.45
    var sideways = side; sideways.gazeOffset = 0.9
    check(scorer.classify(straight, at: 15) == .focused)
    check(scorer.classify(sideways, at: 15) == .lookingAway)
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

func everyFourthBreakIsLong() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 8), at: t0)
    check(clock.breakMinutes(after: 3) == 5 && clock.breakMinutes(after: 4) == 15 && clock.breakMinutes(after: 8) == 15)
    clock.tick(at: t0 + (25 + 5 + 25 + 5 + 25 + 5 + 25) * 60)
    check(clock.phase == .rest(round: 4) && clock.isLongBreak && clock.phaseDuration == 15 * 60)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 20, rounds: 8), at: t0)
    check(clock.breakMinutes(after: 4) == 30)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 30, rounds: 8), at: t0)
    check(clock.breakMinutes(after: 4) == 30)
}

func absenceRespectsCooldown() {
    // Present, gone 25 s, back for 5 s, gone again for 25 s: the second absence is inside the 180 s cooldown.
    check(run(until: 120) { t in (10..<35).contains(t) || (40..<65).contains(t) ? .noFace : look } == [.absent])
}

func absentIsNotCountedBeforeFirstFace() {
    let scorer = FocusScorer(params: .standard, start: 0)
    for i in 0...600 { check(scorer.process(.noFace, at: Double(i) / fps) == nil) } // 60 s at an empty chair
    check(scorer.score == 100)
    var events: [FocusEvent] = []
    for i in 601...1100 { // then a face, then 20 s gone
        let t = Double(i) / fps
        if let e = scorer.process(i < 700 ? look : .noFace, at: t) { events.append(e) }
    }
    check(events == [.absent])
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

func noInstantAlertAfterFrameGap() {
    let scorer = FocusScorer(params: .standard, start: 0)
    var events: [FocusEvent] = []
    for i in 0...1000 { let t = Double(i) / fps; if let e = scorer.process(look, at: t) { events.append(e) } }
    // 5 minutes of nothing (Mac asleep), score window still remembers a drop
    for i in 0...300 { let t = 100 + Double(i) / fps; if let e = scorer.process(away, at: t) { events.append(e) } }
    events = []
    if let e = scorer.process(away, at: 500) { events.append(e) }
    check(events.isEmpty)
}

func delayedCalibrationStillWorks() {
    // No face for the first 15 s (absence alert isn't due yet at 20 s), then normal, then a real distraction.
    let events = run(until: 200) { t in t < 15 ? .noFace : ((100..<130).contains(t) ? away : look) }
    check(events == [.lowFocus])
}

func calibrationUsesMedian() {
    // Looking away for 2 s while calibrating must not shift the baseline.
    let events = run(until: 200) { t in (3..<5).contains(t) ? away : look }
    check(events.isEmpty)
}

func lowConfidenceFramesAreIgnored() {
    let scorer = FocusScorer(params: .standard, start: 0)
    var blurry = away
    blurry.confidence = 0.05
    for i in 0...2000 {
        let t = Double(i) / fps
        check(scorer.process(t > 60 ? blurry : look, at: t) == nil)
    }
    check(scorer.score == 100)
}

func absenceAlertsAgainAfterReturning() {
    let events = run(until: 600) { t in (100..<130).contains(t) || (400..<430).contains(t) ? .noFace : look }
    check(events == [.absent, .absent])
}

func returningFromAbsenceNeedsFreshHold() {
    // Away 60 s (absent bubble), back, then a 3 s glance: no extra low-focus bubble.
    let events = run(until: 400) { t in (100..<160).contains(t) ? .noFace : ((370..<373).contains(t) ? away : look) }
    check(events == [.absent])
}

func singleRoundGoesStraightToDone() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 1), at: t0)
    clock.tick(at: t0 + 25 * 60)
    check(clock.phase == .done)
}

func pauseAfterMissedPhaseCatchesUp() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 2), at: t0)
    clock.pause(at: t0 + 27 * 60)
    check(clock.phase == .rest(round: 1))
    check(clock.remaining(at: t0 + 99 * 60) == 3 * 60)
}

func zeroConfigIsClamped() {
    var clock = SessionClock()
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    clock.start(SessionConfig(studyMinutes: 0, breakMinutes: 0, rounds: 0), at: t0)
    check(clock.config == SessionConfig(studyMinutes: 1, breakMinutes: 1, rounds: 1))
    clock.tick(at: t0 + 1_000_000)
    check(clock.phase == .done)
}

func lcdDigitsAndText() {
    check(SevenSegment.mask(8) == 0b1111111)
    check(SevenSegment.mask(1) == 0b0000110)
    check(SevenSegment.mask(7) == 0b0000111)
    check(ClockText.countdown(24 * 60 + 59.2) == [2, 5, 0, 0])
    check(ClockText.countdown(24 * 60 + 58.5) == [2, 4, 5, 9])
    check(ClockText.countdown(0.2) == [0, 0, 0, 1])
    check(ClockText.countdown(0) == [0, 0, 0, 0])
    check(ClockText.countdown(-5) == [0, 0, 0, 0])
    check(ClockText.countdown(90 * 60) == [9, 0, 0, 0])
    check(ClockText.countdown(10_000_000) == [9, 9, 5, 9])
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    check(ClockText.wall(Date(timeIntervalSince1970: 3600 * 7 + 60 * 5), calendar: cal) == [0, 7, 0, 5])
}

func phaseAnnouncements() {
    check(Phase.study(round: 1).announcement(to: .rest(round: 1)) == .breakStarted)
    check(Phase.rest(round: 1).announcement(to: .study(round: 2)) == .backToWork)
    check(Phase.study(round: 4).announcement(to: .done) == .allDone)
    check(Phase.idle.announcement(to: .study(round: 1)) == nil)
    check(Phase.study(round: 1).announcement(to: .idle) == nil)
}

/// Unusable frames between two distractions must not let the first one's hold carry over.
func lowConfidenceStretchResetsHold() {
    let scorer = FocusScorer(params: .standard, start: 0)
    var blurry = look; blurry.confidence = 0.1
    var first: Double?
    for i in 0...Int(200 * fps) {
        let t = Double(i) / fps
        let s = (100..<120).contains(t) || t >= 130 ? away : (120..<130).contains(t) ? blurry : look
        if scorer.process(s, at: t) != nil, first == nil { first = t }
    }
    check((first ?? 0) >= 139)
}

func spotifyReplyParses() {
    let d = String(NowPlaying.separator)
    let n = NowPlaying.parse(["playing", "Blue", "Joni Mitchell", "Blue", "https://i.scdn.co/image/ab67", "true", "false"].joined(separator: d))
    check(n == NowPlaying(playing: true, title: "Blue", artist: "Joni Mitchell", album: "Blue",
                          artworkURL: URL(string: "https://i.scdn.co/image/ab67"), shuffling: true, repeating: false))
    check(NowPlaying.parse("stopped") == nil) // nothing loaded
    check(NowPlaying.oembedThumbnail(Data(#"{"thumbnail_url":"https://image-cdn-ak.spotifycdn.com/image/ab67"}"#.utf8))
          == URL(string: "https://image-cdn-ak.spotifycdn.com/image/ab67"))
    check(NowPlaying.oembedThumbnail(Data(#"{"thumbnail_url":"https://evil.example/x.jpg"}"#.utf8)) == nil)
    check(NowPlaying.parse(["paused", "A", "B", "C", "file:///etc/passwd", "false", "true"].joined(separator: d))?.artworkURL == nil)
    check(NowPlaying.parse(["paused", "A", "B", "C", "https://evil.example/x.jpg", "false", "true"].joined(separator: d))?.artworkURL == nil)
}

func monoNeverGoesBack() {
    let a = Mono.seconds(), b = Mono.seconds()
    check(b >= a && a > 0)
}

let checks: [(String, () -> Void)] = [
    ("spotifyReplyParses", spotifyReplyParses),
    ("monoNeverGoesBack", monoNeverGoesBack),
    ("lowConfidenceStretchResetsHold", lowConfidenceStretchResetsHold),
    ("noInstantAlertAfterFrameGap", noInstantAlertAfterFrameGap),
    ("delayedCalibrationStillWorks", delayedCalibrationStillWorks),
    ("calibrationUsesMedian", calibrationUsesMedian),
    ("lowConfidenceFramesAreIgnored", lowConfidenceFramesAreIgnored),
    ("absenceAlertsAgainAfterReturning", absenceAlertsAgainAfterReturning),
    ("returningFromAbsenceNeedsFreshHold", returningFromAbsenceNeedsFreshHold),
    ("singleRoundGoesStraightToDone", singleRoundGoesStraightToDone),
    ("pauseAfterMissedPhaseCatchesUp", pauseAfterMissedPhaseCatchesUp),
    ("zeroConfigIsClamped", zeroConfigIsClamped),
    ("secondScreenBecomesAZone", secondScreenBecomesAZone),
    ("zonesCarryOverToTheNextPhase", zonesCarryOverToTheNextPhase),
    ("gazeIsRelativeToCalibration", gazeIsRelativeToCalibration),
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
    ("lcdDigitsAndText", lcdDigitsAndText),
    ("phaseAnnouncements", phaseAnnouncements),
    ("everyFourthBreakIsLong", everyFourthBreakIsLong),
    ("absenceRespectsCooldown", absenceRespectsCooldown),
    ("absentIsNotCountedBeforeFirstFace", absentIsNotCountedBeforeFirstFace),
]
for (name, body) in checks {
    current = name
    let before = failures
    body()
    print(failures == before ? "ok   \(name)" : "FAIL \(name)")
}
print(failures == 0 ? "All \(checks.count) checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
