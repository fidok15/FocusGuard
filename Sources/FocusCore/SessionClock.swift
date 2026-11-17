import Foundation

/// Time that only moves forward and keeps counting while the Mac sleeps. Setting the Mac's clock does not move it,
/// so session deadlines and focus timers use this; only what is shown as wall time (the desk clock, the sky) uses Date().
public enum Mono {
    public static func seconds() -> Double { Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9 }
    public static func now() -> Date { Date(timeIntervalSinceReferenceDate: seconds()) }
}

public struct SessionConfig: Equatable, Sendable {
    public var studyMinutes: Int
    public var breakMinutes: Int
    public var rounds: Int

    public init(studyMinutes: Int, breakMinutes: Int, rounds: Int) {
        self.studyMinutes = studyMinutes
        self.breakMinutes = breakMinutes
        self.rounds = rounds
    }
}

public enum Phase: Equatable, Sendable {
    case idle
    case study(round: Int)
    case rest(round: Int)
    case done

    public var isStudy: Bool { if case .study = self { true } else { false } }
    public var round: Int? {
        switch self {
        case .study(let round), .rest(let round): round
        case .idle, .done: nil
        }
    }
    public var isRunning: Bool {
        switch self {
        case .study, .rest: true
        case .idle, .done: false
        }
    }
}

/// Pomodoro state machine. Pure value type: time is always passed in.
public struct SessionClock: Sendable {
    public private(set) var phase: Phase = .idle
    public private(set) var config = SessionConfig(studyMinutes: 25, breakMinutes: 5, rounds: 4)
    public private(set) var phaseDuration: TimeInterval = 0
    private var phaseEnd: Date?
    private var pausedRemaining: TimeInterval?
    /// Study time of the study phases already over.
    private var studiedBefore: TimeInterval = 0
    /// Where a session ended with stop was, so its summary can take it back.
    private var stopped: (phase: Phase, remaining: TimeInterval)?
    /// After a break the next study round waits, paused, for the user instead of starting by itself.
    public var waitAfterBreak = false

    public init() {}

    public var isPaused: Bool { pausedRemaining != nil }
    /// The phase a stopped session was in; nil when it ran to the end.
    public var stoppedIn: Phase? { stopped?.phase }

    /// Time actually spent in study phases, pauses excluded.
    public func studied(at now: Date) -> TimeInterval {
        let current = stopped.map { $0.phase.isStudy ? phaseDuration - $0.remaining : 0 }
            ?? (phase.isStudy ? phaseDuration - remaining(at: now) : 0)
        return studiedBefore + current
    }

    /// Every 4th break is three times as long, capped at 30 minutes.
    public func breakMinutes(after round: Int) -> Int {
        round % 4 == 0 ? max(config.breakMinutes, min(30, config.breakMinutes * 3)) : config.breakMinutes
    }

    public var isLongBreak: Bool {
        if case .rest(let round) = phase { return breakMinutes(after: round) > config.breakMinutes }
        return false
    }

    public func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let phaseEnd else { return 0 }
        return max(0, phaseEnd.timeIntervalSince(now))
    }

    public mutating func start(_ config: SessionConfig, at now: Date) {
        self.config = SessionConfig(studyMinutes: max(1, config.studyMinutes),
                                    breakMinutes: max(1, config.breakMinutes),
                                    rounds: max(1, config.rounds))
        reset()
        enter(.study(round: 1), at: now)
    }

    /// Back to idle, forgetting the session.
    public mutating func reset() {
        phase = .idle
        phaseEnd = nil
        pausedRemaining = nil
        phaseDuration = 0
        studiedBefore = 0
        stopped = nil
    }

    /// Ends a running session early, on its summary. Stopped within its first seconds, it just goes back to idle.
    public mutating func stop(at now: Date) {
        tick(at: now)
        guard phase.isRunning else { return }
        if studied(at: now) < 10 { return reset() }
        stopped = (phase, remaining(at: now))
        phase = .done
        phaseEnd = nil
        pausedRemaining = nil
    }

    /// Takes a stop back: the session carries on where it was stopped.
    public mutating func undoStop(at now: Date) {
        guard let stopped else { return }
        phase = stopped.phase
        phaseEnd = now.addingTimeInterval(stopped.remaining)
        self.stopped = nil
    }

    /// Ends the break now and starts the next study round.
    public mutating func skipBreak(at now: Date) {
        tick(at: now)
        guard case .rest(let round) = phase else { return }
        pausedRemaining = nil
        enter(.study(round: round + 1), at: now)
    }

    /// Makes the running phase longer, paused or not.
    public mutating func extend(by seconds: TimeInterval, at now: Date) {
        tick(at: now)
        guard phase.isRunning else { return }
        phaseDuration += seconds
        if let pausedRemaining { self.pausedRemaining = pausedRemaining + seconds }
        else { phaseEnd = phaseEnd?.addingTimeInterval(seconds) }
    }

    public mutating func pause(at now: Date) {
        tick(at: now) // catch up on phases that ended while asleep
        guard phase.isRunning, !isPaused else { return }
        pausedRemaining = remaining(at: now)
    }

    public mutating func resume(at now: Date) {
        guard let pausedRemaining else { return }
        phaseEnd = now.addingTimeInterval(pausedRemaining)
        self.pausedRemaining = nil
    }

    /// Advances through every phase that ended before `now` (handles sleep/wake). Returns true if the phase changed.
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        guard !isPaused else { return false }
        var changed = false
        while let end = phaseEnd, now >= end {
            advance(at: end)
            changed = true
        }
        return changed
    }

    private mutating func advance(at time: Date) {
        switch phase {
        case .study(let round) where round >= config.rounds:
            studiedBefore += phaseDuration
            phase = .done
            phaseEnd = nil
        case .study(let round):
            studiedBefore += phaseDuration
            enter(.rest(round: round), at: time)
        case .rest(let round):
            enter(.study(round: round + 1), at: time)
            if waitAfterBreak { // the round stays at its full length until resumed
                pausedRemaining = phaseDuration
                phaseEnd = nil
            }
        case .idle, .done:
            phaseEnd = nil
        }
    }

    private mutating func enter(_ phase: Phase, at time: Date) {
        self.phase = phase
        var minutes = config.studyMinutes
        if case .rest(let round) = phase { minutes = breakMinutes(after: round) }
        phaseDuration = TimeInterval(minutes * 60)
        phaseEnd = time.addingTimeInterval(phaseDuration)
    }
}
