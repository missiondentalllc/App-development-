import Foundation

/// Memory reinforcement: skills come back for review at growing gaps
/// (1, 2, 4, 8, 16, 32, 64 days). A miss sends the skill back to tomorrow.
public enum SpacedReview {
    public static let intervalsInDays: [Int] = [1, 2, 4, 8, 16, 32, 64]

    public static func schedule(_ state: SkillState, correct: Bool, fast: Bool,
                                at date: Date, calendar: Calendar = .current) -> SkillState {
        var s = state
        if !correct {
            s.reviewBox = 0
        } else if fast {
            s.reviewBox = min(s.reviewBox + 1, intervalsInDays.count - 1)
        }
        // Right but slow: stay in the same box.
        let days = intervalsInDays[s.reviewBox]
        s.nextReview = calendar.date(byAdding: .day, value: days, to: date)
        return s
    }

    public static func isDue(_ s: SkillState, now: Date = Date()) -> Bool {
        guard s.attempts > 0, let next = s.nextReview else { return false }
        return next <= now
    }
}
