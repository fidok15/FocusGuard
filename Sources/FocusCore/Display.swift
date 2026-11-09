import Foundation

/// Pure logic behind the desk clock's LCD and the phase-change announcements.
public enum SevenSegment {
    /// Segments lit for a digit 0...9 as bits: a=1 (top), b=2 (top right), c=4 (bottom right), d=8 (bottom),
    /// e=16 (bottom left), f=32 (top left), g=64 (middle).
    public static func mask(_ digit: Int) -> UInt8 {
        let table: [UInt8] = [0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
                              0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111]
        return table[min(max(digit, 0), 9)]
    }
}

public enum ClockText {
    /// Four digits `[m, m, s, s]` for a countdown. Seconds round up, so 0:00 only shows when time is really out.
    public static func countdown(_ remaining: TimeInterval) -> [Int] {
        let s = min(max(Int(remaining.rounded(.up)), 0), 99 * 60 + 59)
        return digits(s / 60, s % 60)
    }

    /// Four digits `[h, h, m, m]` of local wall-clock time (24 hour).
    public static func wall(_ date: Date, calendar: Calendar = .current) -> [Int] {
        digits(calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }

    private static func digits(_ a: Int, _ b: Int) -> [Int] { [a / 10, a % 10, b / 10, b % 10] }
}

public enum Announcement: Equatable, Sendable {
    case breakStarted, backToWork, allDone
}

extension Phase {
    /// What to tell the user when the clock moved from `self` to `new` by itself (not by start/stop).
    public func announcement(to new: Phase) -> Announcement? {
        switch (self, new) {
        case (.study, .rest): .breakStarted
        case (.rest, .study): .backToWork
        case (.study, .done), (.rest, .done): .allDone
        default: nil
        }
    }
}
