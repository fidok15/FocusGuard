import Foundation

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

    public init() {}

    public var isPaused: Bool { pausedRemaining != nil }

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
        pausedRemaining = nil
        enter(.study(round: 1), at: now)
    }

    public mutating func stop() {
        phase = .idle
        phaseEnd = nil
        pausedRemaining = nil
        phaseDuration = 0
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
            phase = .done
            phaseEnd = nil
        case .study(let round):
            enter(.rest(round: round), at: time)
        case .rest(let round):
            enter(.study(round: round + 1), at: time)
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
