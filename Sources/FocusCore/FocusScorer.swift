import Foundation

/// What the face analyzer saw in one camera frame.
public struct FaceSignals: Sendable {
    public var faceFound: Bool
    /// Eye openness: eye height / eye width, averaged over both eyes.
    public var ear: Double
    /// 0 = pupil centered in the eye, 1 = pupil at the eye corner.
    public var gazeOffset: Double
    /// Head rotation in degrees.
    public var yaw: Double
    public var pitch: Double
    /// Landmark confidence 0...1.
    public var confidence: Double

    public init(faceFound: Bool, ear: Double, gazeOffset: Double, yaw: Double, pitch: Double, confidence: Double) {
        self.faceFound = faceFound
        self.ear = ear
        self.gazeOffset = gazeOffset
        self.yaw = yaw
        self.pitch = pitch
        self.confidence = confidence
    }

    public static let noFace = FaceSignals(faceFound: false, ear: 0, gazeOffset: 0, yaw: 0, pitch: 0, confidence: 1)
}

public enum FrameState: Equatable, Sendable {
    case focused, lookingAway, eyesClosed, absent, skipped
}

public enum FocusEvent: Equatable, Sendable {
    case lowFocus
    case absent
}

/// Window W (s), threshold T (%), hold H (s), cooldown C (s).
public struct ScorerParams: Equatable, Sendable {
    public var window: Double
    public var threshold: Double
    public var hold: Double
    public var cooldown: Double

    public static let gentle = ScorerParams(window: 60, threshold: 40, hold: 20, cooldown: 300)
    public static let standard = ScorerParams(window: 30, threshold: 50, hold: 10, cooldown: 180)
    public static let sensitive = ScorerParams(window: 15, threshold: 60, hold: 5, cooldown: 90)

    /// 0 = gentle, 0.5 = standard, 1 = sensitive, linear in between.
    public static func forSensitivity(_ value: Double) -> ScorerParams {
        let s = min(max(value, 0), 1)
        let (a, b, f) = s < 0.5 ? (gentle, standard, s * 2) : (standard, sensitive, (s - 0.5) * 2)
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return ScorerParams(window: lerp(a.window, b.window), threshold: lerp(a.threshold, b.threshold),
                            hold: lerp(a.hold, b.hold), cooldown: lerp(a.cooldown, b.cooldown))
    }
}

/// Calibration knobs, ported from the ideas in e-candeloro/Driver-State-Detection (MIT).
/// ponytail: fixed constants tuned for a laptop webcam; expose in settings if users report false alerts.
public enum Knobs {
    public static let calibrationSeconds = 10.0
    public static let gracePeriod = 60.0
    public static let eyesClosedRatio = 0.7
    public static let eyesClosedMinDuration = 0.5
    public static let maxYaw = 25.0
    public static let maxPitch = 20.0
    public static let maxGazeOffset = 0.35
    public static let minConfidence = 0.2
    public static let absentAlertAfter = 20.0
    /// Alert only while the user is still distracted right now, not after they came back.
    public static let recentWindow = 2.0
    public static let displaySmoothing = 0.05
    /// Baseline needs this many good frames (~3 s at 10 fps) after the calibration time.
    public static let calibrationSamples = 30
    /// A head pose you held for this long in total over the last `zoneMemory` seconds becomes a work zone (a second screen).
    public static let zoneLearnAfter = 60.0
    public static let zoneMemory = 600.0
    /// Poses further than this above or below the calibrated one are never learned: that is a phone in your lap, not a screen.
    public static let zoneMaxPitch = 30.0
}

/// Head poses you keep coming back to: a second monitor, a laptop beside it. Lives across study phases, so a screen
/// learned in round one is still a screen in round two. Poses go into 10° bins; a pose is in a zone when its bin and
/// the bins around it (about ±15°) add up to `zoneLearnAfter` seconds within the last `zoneMemory` seconds.
/// ponytail: frames are counted as 0.1 s each, true at the camera's fixed ~10 fps.
public final class PoseZones {
    private struct Bin: Hashable { let yaw: Int, pitch: Int }
    private var samples: [(t: Double, bin: Bin)] = []
    private var counts: [Bin: Int] = [:]

    public init() {}

    private static func bin(_ yaw: Double, _ pitch: Double) -> Bin {
        Bin(yaw: Int((yaw / 10).rounded()), pitch: Int((pitch / 10).rounded()))
    }

    private func forget(before t: Double) {
        var drop = 0
        while drop < samples.count, samples[drop].t < t - Knobs.zoneMemory {
            counts[samples[drop].bin]! -= 1
            drop += 1
        }
        if drop > 0 { samples.removeFirst(drop) }
    }

    public func record(yaw: Double, pitch: Double, at t: Double) {
        forget(before: t)
        let b = Self.bin(yaw, pitch)
        samples.append((t, b))
        counts[b, default: 0] += 1
    }

    public func contains(yaw: Double, pitch: Double, at t: Double) -> Bool {
        forget(before: t)
        let b = Self.bin(yaw, pitch)
        var frames = 0
        for dy in -1...1 { for dp in -1...1 { frames += counts[Bin(yaw: b.yaw + dy, pitch: b.pitch + dp)] ?? 0 } }
        return Double(frames) * 0.1 >= Knobs.zoneLearnAfter
    }
}

/// Turns per-frame face signals into a windowed focus score and rare, non-spammy alerts.
/// Pure logic: no camera, no UI, time passed in as seconds.
/// One scorer covers one stretch of studying: the app creates a fresh one for every study phase and on resume,
/// which re-runs calibration and the grace period.
/// ponytail: the score is a frame ratio, not time-weighted; fine at the camera's fixed ~10 fps.
public final class FocusScorer {
    public var params: ScorerParams
    public private(set) var score: Double = 100
    public private(set) var smoothedScore: Double = 100
    public var isCalibrating: Bool { baseline == nil }

    private let start: Double
    private var samples: [(t: Double, focused: Bool)] = []
    private var calibration: [FaceSignals] = []
    private var baseline: (yaw: Double, pitch: Double, ear: Double, gaze: Double)?
    private var closedSince: Double?
    private var absentSince: Double?
    /// Nobody counts as absent before the first face of this stretch: coming back late from a break is not a lapse.
    private var faceSeen = false
    private var absentAlerted = false
    private var belowSince: Double?
    private var lastAlert: Double?
    /// Time of the last frame that counted (not skipped); the app hides the focus figure once this goes stale.
    public private(set) var lastFrame: Double?

    private let zones: PoseZones

    public init(params: ScorerParams, start: Double, zones: PoseZones = PoseZones()) {
        self.params = params
        self.start = start
        self.zones = zones
    }

    @discardableResult
    public func process(_ signals: FaceSignals, at t: Double) -> FocusEvent? {
        // After a gap in frames (sleep, camera stall, long low-confidence stretch) old timers no longer mean anything.
        if let last = lastFrame, t - last > Knobs.recentWindow {
            belowSince = nil
            closedSince = nil
            absentSince = nil
        }
        let state = classify(signals, at: t)
        guard state != .skipped else { return nil }
        lastFrame = t // only frames that count: a long run of skipped ones is a gap too

        samples.append((t, state == .focused))
        while let first = samples.first, first.t < t - params.window { samples.removeFirst() }
        score = Double(samples.filter(\.focused).count) / Double(samples.count) * 100
        smoothedScore += (score - smoothedScore) * Knobs.displaySmoothing

        return evaluate(at: t)
    }

    public func classify(_ s: FaceSignals, at t: Double) -> FrameState {
        guard s.faceFound else {
            guard faceSeen else { return .skipped }
            if absentSince == nil { absentSince = t }
            closedSince = nil
            return .absent
        }
        faceSeen = true
        if absentSince != nil {
            // Back at the desk: the windowed score still lags, so don't let it count as an already-held drop.
            absentSince = nil
            belowSince = nil
        }
        absentAlerted = false
        guard s.confidence >= Knobs.minConfidence else {
            closedSince = nil
            return .skipped
        }

        guard let base = baseline else {
            calibration.append(s)
            if t - start >= Knobs.calibrationSeconds, calibration.count >= Knobs.calibrationSamples {
                // Median, so a glance away during calibration doesn't skew the baseline.
                func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
                baseline = (median(calibration.map(\.yaw)), median(calibration.map(\.pitch)), median(calibration.map(\.ear)),
                            median(calibration.map(\.gazeOffset)))
                calibration = []
            }
            return .focused
        }

        if s.ear < base.ear * Knobs.eyesClosedRatio {
            let since = closedSince ?? t
            closedSince = since
            if t - since > Knobs.eyesClosedMinDuration { return .eyesClosed }
        } else {
            closedSince = nil
        }

        // Every pose that could be a screen is remembered, so a second monitor becomes a zone after a minute or so.
        if abs(s.pitch - base.pitch) <= Knobs.zoneMaxPitch { zones.record(yaw: s.yaw, pitch: s.pitch, at: t) }
        if abs(s.yaw - base.yaw) > Knobs.maxYaw || abs(s.pitch - base.pitch) > Knobs.maxPitch {
            return zones.contains(yaw: s.yaw, pitch: s.pitch, at: t) ? .focused : .lookingAway
        }
        // Relative to calibration: a camera off to the side sees the eye at an angle, so the pupil never sits centred.
        return s.gazeOffset - base.gaze > Knobs.maxGazeOffset ? .lookingAway : .focused
    }

    private func evaluate(at t: Double) -> FocusEvent? {
        belowSince = score < params.threshold ? (belowSince ?? t) : nil

        if let since = absentSince {
            guard !absentAlerted, t - since >= Knobs.absentAlertAfter else { return nil }
            if let lastAlert, t - lastAlert < params.cooldown { return nil } // stepping in and out of frame must not nag
            absentAlerted = true
            // Shares the cooldown on purpose: coming back to a low score must not pop a second bubble right away.
            lastAlert = t
            return .absent
        }

        guard t - start >= Knobs.gracePeriod,
              let below = belowSince, t - below >= params.hold else { return nil }
        let recent = samples.filter { $0.t >= t - Knobs.recentWindow }
        guard Double(recent.filter(\.focused).count) < Double(recent.count) * 0.5 else { return nil }
        if let lastAlert, t - lastAlert < params.cooldown { return nil }
        lastAlert = t
        return .lowFocus
    }
}
