import Foundation

/// One learner (e.g. Charlotte, Mayli). Each learner has their own progress.
public struct Profile: Codable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    /// curriculumId -> skillId -> state
    public var progress: [String: [String: SkillState]]
    /// First-grade plan: the day the learner is on, per curriculum.
    public var currentDay: [String: Int]
    public var sessions: [StudySession]

    public init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.progress = [:]
        self.currentDay = [:]
        self.sessions = []
    }

    public func state(_ skillId: String, in curriculumId: String) -> SkillState {
        progress[curriculumId]?[skillId] ?? SkillState()
    }

    public mutating func setState(_ state: SkillState, for skillId: String, in curriculumId: String) {
        var map = progress[curriculumId] ?? [:]
        map[skillId] = state
        progress[curriculumId] = map
    }

    /// Active study seconds on a calendar day — subtract this from screen time.
    public func studySeconds(on day: Date, calendar: Calendar = .current) -> TimeInterval {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.activeSeconds }
    }
}

/// What the app knows about one learner on one skill.
public struct SkillState: Codable, Hashable {
    public var attempts: Int = 0
    public var correct: Int = 0
    /// 0...1. Blends accuracy and speed; fast-and-right scores far above slow-and-right.
    public var comprehension: Double = 0
    /// True when set by the placement test rather than earned by practice.
    public var provisional: Bool = false
    public var lastPracticed: Date?
    /// Spaced-review box (0 = review tomorrow, higher = longer gaps).
    public var reviewBox: Int = 0
    public var nextReview: Date?
    public var averageSeconds: Double?
    /// Difficulty tier: 1 Starter, 2 Core, 3 Challenge. Nil for progress saved before tiers existed.
    public var tier: Int?
    public var rightStreak: Int?
    public var missStreak: Int?

    public init() {}

    public var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

/// One timestamped, pausable study session. Partial sessions still count.
public struct StudySession: Codable, Identifiable, Hashable {
    public let id: UUID
    public let curriculumId: String
    public let startedAt: Date
    public var endedAt: Date?
    /// Time actually studying, with pauses removed.
    public var activeSeconds: TimeInterval
    public var attempts: [Attempt]

    public init(curriculumId: String, startedAt: Date = Date()) {
        self.id = UUID()
        self.curriculumId = curriculumId
        self.startedAt = startedAt
        self.activeSeconds = 0
        self.attempts = []
    }
}

/// One answered question.
public struct Attempt: Codable, Hashable {
    public let skillId: String
    public let prompt: String
    public let given: String
    public let correct: Bool
    public let seconds: Double
    public let at: Date

    public init(skillId: String, prompt: String, given: String, correct: Bool, seconds: Double, at: Date = Date()) {
        self.skillId = skillId
        self.prompt = prompt
        self.given = given
        self.correct = correct
        self.seconds = seconds
        self.at = at
    }
}
