import Foundation

/// A whole curriculum (for example, First Grade or the Math Ladder).
/// Loaded from a JSON file in `content/`. See `content/SCHEMA.md`.
public struct Curriculum: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let version: Int
    public let stages: [Stage]
    public let skills: [Skill]
    /// Abbreviations used in this curriculum and what they mean (LCM, SD, sin…).
    public let glossary: [GlossaryEntry]?

    public init(id: String, title: String, version: Int, stages: [Stage], skills: [Skill],
                glossary: [GlossaryEntry]? = nil) {
        self.id = id
        self.title = title
        self.version = version
        self.stages = stages
        self.skills = skills
        self.glossary = glossary
    }

    /// Glossary entries whose short form appears in any of the texts, in glossary order.
    public func shortForms(in texts: [String?]) -> [GlossaryEntry] {
        let text = texts.compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return (glossary ?? []).filter { entry in
            let pattern = "(?<![A-Za-z-])" + NSRegularExpression.escapedPattern(for: entry.term) + "s?(?![A-Za-z-])"
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            return re.firstMatch(in: text, range: range) != nil
        }
    }

    public func skill(_ id: String) -> Skill? { skills.first { $0.id == id } }

    public func skills(in stageId: String) -> [Skill] { skills.filter { $0.stage == stageId } }

    public func stage(_ id: String) -> Stage? { stages.first { $0.id == id } }
}

/// One abbreviation and its plain-English meaning.
public struct GlossaryEntry: Codable, Hashable {
    public let term: String
    public let meaning: String

    public init(term: String, meaning: String) {
        self.term = term
        self.meaning = meaning
    }
}

/// A band of the curriculum: a grade, a course, or a level.
public struct Stage: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let order: Int
    public let level: String?        // e.g. "Grade 1", "High school", "Graduate"
    public let description: String?
    /// Three ways to teach this level (shown until every skill in it is fully mastered).
    public var approaches: Approaches? = nil
}

/// Three teaching approaches, used in this order after each miss.
public struct Approaches: Codable, Hashable {
    /// The tutor shows it while the learner watches.
    public let show: String
    /// Tutor and learner do one together, taking turns.
    public let together: String
    /// The learner tries one alone; one hint only if stuck.
    public let alone: String

    public static let names = ["Show", "Do together", "Try alone"]
    public static let blurbs = ["You show it while they watch.",
                                "Do one together, taking turns.",
                                "They try one alone; you give one hint only if stuck."]

    public func text(_ index: Int) -> String { [show, together, alone][index % 3] }
}

/// The three parts of every level.
public enum Part {
    public static let names = [1: "Foundations", 2: "Building", 3: "Mastery"]
}

/// One teachable skill (a "topic" in the first-grade plan).
public struct Skill: Codable, Identifiable, Hashable {
    public let id: String
    public let stage: String
    /// Part 1 (Foundations), 2 (Building) or 3 (Mastery) of the level.
    public var part: Int? = nil
    public let title: String
    public let summary: String
    public let prerequisites: [String]
    public let lesson: Lesson
    public let practice: Practice
    /// How this skill gets reused later (memory reinforcement / builds-on note).
    public let reinforcement: String?
    /// First-grade plan only: which day (1–110) this topic is taught.
    public let day: Int?
    /// First-grade plan only: Math, Reading, Writing, Science, Social Studies.
    public let subject: String?
    /// Seconds per question that counts as "sight pace" for this skill.
    public let sightPaceSeconds: Double?

    public var hasPractice: Bool {
        practice.generator != nil || !(practice.items ?? []).isEmpty
    }
}

public struct Lesson: Codable, Hashable {
    public let explanation: String
    public let example: String?
    public let tutorSteps: [String]?
    /// Three ways to teach this skill (shown until the skill is fully mastered).
    public var approaches: Approaches? = nil
}

public struct Practice: Codable, Hashable {
    /// Key of a built-in question generator (see `QuestionGenerators`).
    public let generator: String?
    public let params: [String: Int]?
    /// Hand-written questions.
    public let items: [Item]?
}

public struct Item: Codable, Hashable {
    public let prompt: String
    /// Multiple choice options. When present, `answer` must be one of them.
    public let choices: [String]?
    /// Correct answer. Ignored for tutor-judged items.
    public let answer: String?
    /// "auto" (default) or "tutor" — the tutor marks it right/wrong (reading aloud, writing).
    public let mode: String?
    /// Difficulty: 1 Starter, 2 Core, 3 Challenge (the full skill). Nil fits any tier.
    public var tier: Int? = nil
}
