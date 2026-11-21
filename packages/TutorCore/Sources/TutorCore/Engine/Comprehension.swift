import Foundation

/// Turns answers into a comprehension score per skill.
///
/// Rules (from the product plan):
/// - Every question is capped at 60 seconds.
/// - Right and at sight pace counts fully. Right but slow counts much less.
///   100% right and fast ≈ 1.0; 100% right at the 60 s cap ≈ 0.5.
/// - Wrong counts 0.
/// - Recent answers weigh more than old ones (moving average).
public enum Comprehension {
    public static let questionCapSeconds: Double = 60
    public static let defaultSightPace: Double = 5
    /// Weight of the newest answer in the moving average.
    public static let smoothing: Double = 0.3

    public static let passThreshold = 0.70      // unlocks what depends on it
    public static let masteryThreshold = 0.85   // mastered
    public static let sightThreshold = 0.95     // sight-level fluency
    public static let minAttemptsForMastery = 5

    /// 1.0 at or under sight pace, falling to 0.0 at the cap.
    public static func speedScore(seconds: Double, sightPace: Double) -> Double {
        let pace = max(1, sightPace)
        if seconds <= pace { return 1 }
        if seconds >= questionCapSeconds { return 0 }
        return (questionCapSeconds - seconds) / (questionCapSeconds - pace)
    }

    /// Score for a single answer.
    public static func answerScore(correct: Bool, seconds: Double, sightPace: Double) -> Double {
        guard correct else { return 0 }
        return 0.5 + 0.5 * speedScore(seconds: seconds, sightPace: sightPace)
    }

    /// Update a skill's state after one answer.
    public static func record(_ state: SkillState, correct: Bool, seconds: Double,
                              sightPace: Double?, at date: Date = Date()) -> SkillState {
        var s = state
        let pace = sightPace ?? defaultSightPace
        let clamped = min(max(seconds, 0), questionCapSeconds)
        let score = answerScore(correct: correct, seconds: clamped, sightPace: pace)

        if s.attempts == 0 || s.provisional {
            s.comprehension = score
        } else {
            s.comprehension = smoothing * score + (1 - smoothing) * s.comprehension
        }
        s.provisional = false
        s.attempts += 1
        if correct { s.correct += 1 }
        s.averageSeconds = ((s.averageSeconds ?? clamped) * Double(s.attempts - 1) + clamped) / Double(s.attempts)
        s.lastPracticed = date
        s = SpacedReview.schedule(s, correct: correct, fast: clamped <= pace * 1.5, at: date)
        return s
    }

    public static func level(_ s: SkillState) -> Level {
        if s.attempts == 0 && !s.provisional { return .new }
        if s.comprehension >= sightThreshold && s.attempts >= minAttemptsForMastery { return .sight }
        if s.comprehension >= masteryThreshold && (s.attempts >= minAttemptsForMastery || s.provisional) { return .mastered }
        if s.comprehension >= passThreshold { return .passing }
        return .learning
    }

    public static func isPassed(_ s: SkillState) -> Bool { s.comprehension >= passThreshold }

    public enum Level: String, Codable, CaseIterable {
        case new, learning, passing, mastered, sight

        public var label: String {
            switch self {
            case .new: return "Not started"
            case .learning: return "Learning"
            case .passing: return "Passing"
            case .mastered: return "Mastered"
            case .sight: return "Sight-level"
            }
        }
    }
}
