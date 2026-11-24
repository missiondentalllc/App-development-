import Foundation

/// A question ready to show on screen.
public struct Question: Identifiable, Hashable {
    public let id = UUID()
    public let skillId: String
    public let prompt: String
    public let choices: [String]?
    public let answer: String?
    /// True when the tutor marks the answer (reading aloud, handwriting, etc.).
    public let tutorJudged: Bool
    /// Difficulty tier this question was made for (1 Starter, 2 Core, 3 Challenge).
    public var tier: Int = 3

    public init(skillId: String, prompt: String, choices: [String]? = nil,
                answer: String?, tutorJudged: Bool = false) {
        self.skillId = skillId
        self.prompt = prompt
        self.choices = choices
        self.answer = answer
        self.tutorJudged = tutorJudged
    }

    public func check(_ given: String) -> Bool {
        guard let answer else { return false }
        return AnswerChecker.matches(given, answer)
    }
}

/// Lenient answer matching: ignores spaces and case, and treats equal numbers
/// as equal ("0.5" = "1/2" = "2/4", "07" = "7").
public enum AnswerChecker {
    public static func matches(_ given: String, _ expected: String) -> Bool {
        let g = normalize(given), e = normalize(expected)
        if g == e { return true }
        if let a = number(g), let b = number(e) { return abs(a - b) < 1e-9 }
        return false
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses integers, decimals and simple fractions like "3/4" or "-2/5".
    static func number(_ s: String) -> Double? {
        if let d = Double(s) { return d }
        let parts = s.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 { return n / d }
        return nil
    }
}

/// Small deterministic random generator so tests (and replays) are repeatable.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
