import Foundation
import Combine

/// Runs one study session: picks questions, times answers (pauses excluded),
/// scores them, shows the lesson again after a miss, and saves after every
/// answer so a session stopped halfway still counts.
@MainActor
public final class PracticeSession: ObservableObject {

    public enum Mode {
        /// Engine decides: repair gaps, review, then advance (Math Ladder).
        case adaptive
        /// Today's topics, then memory review of earlier ones (First Grade lesson).
        case focus(skillIds: [String], reviewCount: Int)
        /// Placement test.
        case diagnostic
    }

    public struct Feedback: Equatable {
        public let correct: Bool
        public let expected: String?
        /// What the learner answered.
        public let given: String
        /// Why the answer is right (shown after any answer).
        public let why: String?
        public let seconds: Double
        public let sightPace: Bool
        /// The tutor marked a handwritten answer right after the app said no.
        public var overridden = false
    }

    @Published public private(set) var question: Question?
    @Published public private(set) var currentSkill: Skill?
    @Published public private(set) var reason: SkillPicker.Reason = .advance
    @Published public private(set) var feedback: Feedback?
    /// Set after a miss: show this skill's lesson before the next question.
    @Published public private(set) var lessonToShow: Skill?
    /// Set after a miss: which teaching approach to show (0 Show, 1 Do together, 2 Try alone).
    @Published public private(set) var approachIndex: Int?
    private var missesBySkill: [String: Int] = [:]
    /// Kept so the tutor can mark a handwriting check as right after all.
    private var undo: (skillId: String, before: SkillState, seconds: Double, attempt: Int, misses: Int)?
    @Published public private(set) var isPaused = false
    @Published public private(set) var answered = 0
    @Published public private(set) var correct = 0
    @Published public private(set) var finished = false

    public let curriculum: Curriculum
    public let graph: SkillGraph
    @Published public private(set) var goal: Int
    /// Skills skipped during this session.
    @Published public private(set) var skippedCount = 0
    private var sessionSkips: Set<String> = []
    private let skippedForGood: Set<String>
    private var planIndex = 0
    public private(set) var profile: Profile
    public private(set) var diagnostic: Diagnostic?

    private let store: ProfileStore
    private let mode: Mode
    private let picker: SkillPicker
    private let factory = QuestionFactory()
    private var session: StudySession
    private var plan: [String] = []

    private var questionStartedAt = Date()
    private var pausedDuringQuestion: TimeInterval = 0
    private var pausedAt: Date?
    private var activeSince: Date?

    public init(curriculum: Curriculum, profile: Profile, store: ProfileStore, mode: Mode, goal: Int = 20) {
        let g = SkillGraph(curriculum)
        var plannedSkills: [String] = []
        var placement: Diagnostic?
        var sessionGoal = goal

        switch mode {
        case .adaptive:
            break
        case .focus(let ids, let reviewCount):
            // Practicing one chosen skill always works; level, part and review practice leave out skipped skills.
            let skippedIds = profile.skippedSkills(in: curriculum.id)
            let focus = ids.filter { g.skill($0)?.hasPractice == true && (ids.count == 1 || !skippedIds.contains($0)) }
            let perSkill = focus.isEmpty ? 0 : max(1, goal / focus.count)
            for _ in 0..<perSkill { plannedSkills.append(contentsOf: focus) }
            plannedSkills.append(contentsOf: PracticeSession.reviewSkills(count: reviewCount, excluding: Set(ids).union(skippedIds),
                                                               graph: g, profile: profile, curriculumId: curriculum.id))
            sessionGoal = plannedSkills.count
        case .diagnostic:
            let d = Diagnostic(graph: g)
            placement = d
            sessionGoal = curriculum.stages.count * d.questionsPerStage
        }

        self.curriculum = curriculum
        self.graph = g
        self.picker = SkillPicker(graph: g)
        self.profile = profile
        self.store = store
        self.mode = mode
        self.session = StudySession(curriculumId: curriculum.id)
        self.plan = plannedSkills
        self.diagnostic = placement
        self.goal = sessionGoal
        self.skippedForGood = profile.skippedSkills(in: curriculum.id)
    }

    // MARK: Flow

    public func start() {
        activeSince = Date()
        advance()
    }

    /// Typed or tapped answer.
    public func submit(_ given: String) {
        guard let q = question, feedback == nil, !isPaused else { return }
        record(given: given, correct: q.check(given), seconds: elapsed())
    }

    /// Tutor marks a read-aloud / written answer.
    public func judge(correct isCorrect: Bool) {
        guard let q = question, feedback == nil, !isPaused, q.tutorJudged else { return }
        record(given: isCorrect ? "tutor: correct" : "tutor: incorrect", correct: isCorrect, seconds: elapsed())
    }

    /// Called when the 60-second cap runs out.
    public func timeUp() {
        guard question != nil, feedback == nil, !isPaused else { return }
        record(given: "(time up)", correct: false, seconds: Comprehension.questionCapSeconds)
    }

    /// Move on after feedback (and after the lesson, if one was shown).
    /// A written answer, already checked by the handwriting checker.
    public func submitWritten(read: String, correct isCorrect: Bool) {
        guard let q = question, q.write, feedback == nil, !isPaused else { return }
        record(given: read.isEmpty ? "(blank)" : read, correct: isCorrect, seconds: elapsed())
    }

    /// The tutor says a handwritten answer the app marked wrong was right after all.
    public func overrideLast() {
        guard let u = undo, let fb = feedback, !fb.correct, question?.write == true,
              let skill = graph.skill(u.skillId) else { return }
        let fixed = Comprehension.record(u.before, correct: true, seconds: u.seconds, sightPace: skill.sightPaceSeconds)
        profile.setState(fixed, for: skill.id, in: curriculum.id)
        if u.attempt < session.attempts.count {
            let a = session.attempts[u.attempt]
            session.attempts[u.attempt] = Attempt(skillId: a.skillId, prompt: a.prompt, given: a.given + " (tutor: correct)",
                                                  correct: true, seconds: a.seconds, at: a.at)
        }
        missesBySkill[skill.id] = u.misses
        correct += 1
        feedback = Feedback(correct: true, expected: fb.expected, given: fb.given, why: fb.why,
                            seconds: fb.seconds, sightPace: false, overridden: true)
        lessonToShow = nil
        approachIndex = nil
        persist()
    }

    /// True when the current skill can be skipped (not during the placement test).
    public var canSkip: Bool { diagnostic == nil && question != nil && feedback == nil && !isPaused && !finished }

    /// Skip the current skill for the rest of this session. Nothing is scored.
    public func skip() {
        guard canSkip, let id = currentSkill?.id else { return }
        sessionSkips.insert(id)
        skippedCount += 1
        if case .focus = mode {
            plan = Array(plan[..<planIndex]) + plan[planIndex...].filter { $0 != id }
            goal = plan.count
        }
        advance()
    }

    public func next() {
        feedback = nil
        lessonToShow = nil
        approachIndex = nil
        advance()
    }

    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        let now = Date()
        pausedAt = now
        if let since = activeSince { session.activeSeconds += now.timeIntervalSince(since) }
        activeSince = nil
        persist()
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        let now = Date()
        if let at = pausedAt { pausedDuringQuestion += now.timeIntervalSince(at) }
        pausedAt = nil
        activeSince = now
    }

    /// End early or at the finish. Everything answered so far is kept.
    public func end() {
        if let since = activeSince { session.activeSeconds += Date().timeIntervalSince(since) }
        activeSince = nil
        session.endedAt = Date()
        if let diagnostic {
            let states = diagnostic.apply(to: profile.progress[curriculum.id] ?? [:])
            profile.progress[curriculum.id] = states
        }
        finished = true
        question = nil
        persist()
    }

    /// Seconds spent on the current question, pauses removed.
    public func elapsed(now: Date = Date()) -> Double {
        let paused = pausedDuringQuestion + (pausedAt.map { now.timeIntervalSince($0) } ?? 0)
        return max(0, now.timeIntervalSince(questionStartedAt) - paused)
    }

    public var activeSeconds: TimeInterval {
        session.activeSeconds + (activeSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: Internals

    private func record(given: String, correct isCorrect: Bool, seconds: Double) {
        guard let q = question, let skill = currentSkill else { return }
        let secs = min(seconds, Comprehension.questionCapSeconds)
        let old = profile.state(skill.id, in: curriculum.id)
        undo = (skill.id, old, secs, session.attempts.count, missesBySkill[skill.id] ?? 0)
        let new = Comprehension.record(old, correct: isCorrect, seconds: secs, sightPace: skill.sightPaceSeconds)
        profile.setState(new, for: skill.id, in: curriculum.id)
        session.attempts.append(Attempt(skillId: skill.id, prompt: q.prompt, given: given, correct: isCorrect, seconds: secs))
        diagnostic?.record(skill: skill, correct: isCorrect, seconds: secs)

        answered += 1
        planIndex += 1
        if isCorrect { correct += 1 }
        let pace = skill.sightPaceSeconds ?? Comprehension.defaultSightPace
        feedback = Feedback(correct: isCorrect, expected: q.tutorJudged ? nil : q.answer,
                            given: given, why: q.why,
                            seconds: secs, sightPace: isCorrect && secs <= pace)
        if !isCorrect, diagnostic == nil {
            lessonToShow = skill
            // Each miss on a skill brings the next teaching approach: Show, Do together, Try alone.
            let misses = (missesBySkill[skill.id] ?? 0) + 1
            missesBySkill[skill.id] = misses
            approachIndex = (misses - 1) % 3
        }
        persist()
    }

    private func advance() {
        // The placement test asks Challenge questions; practice asks at the learner's tier.
        let tierFor: (Skill) -> Int = { [self] s in
            diagnostic != nil ? 3 : Tiers.current(profile.state(s.id, in: curriculum.id))
        }
        guard let skill = nextSkill(), let q = factory.question(for: skill, tier: tierFor(skill)) else {
            end()
            return
        }
        currentSkill = skill
        question = q
        questionStartedAt = Date()
        pausedDuringQuestion = 0
    }

    private func nextSkill() -> Skill? {
        switch mode {
        case .adaptive:
            guard answered < goal else { return nil }
            let states = profile.progress[curriculum.id] ?? [:]
            let leaveOut = skippedForGood.union(sessionSkips)
            var pick = picker.next(states: states, excluding: leaveOut, skipped: skippedForGood)
            // If skipping left nothing open, let this session's skips unlock what builds on them too.
            if pick.skill == nil && !sessionSkips.isEmpty {
                pick = picker.next(states: states, excluding: leaveOut, skipped: leaveOut)
            }
            reason = pick.reason
            return pick.skill
        case .focus:
            guard planIndex < plan.count else { return nil }
            reason = planIndex < plan.count - reviewTail ? .advance : .review
            return graph.skill(plan[planIndex])
        case .diagnostic:
            guard let d = diagnostic, !d.finished else { return nil }
            reason = .advance
            return d.nextSkill()
        }
    }

    private var reviewTail: Int {
        if case .focus(_, let n) = mode { return min(n, plan.count) }
        return 0
    }

    private func persist() {
        // Save a snapshot that includes the time studied so far, so leaving the
        // screen without pressing End still records the study time.
        var snapshot = session
        snapshot.activeSeconds = activeSeconds
        if let i = profile.sessions.firstIndex(where: { $0.id == session.id }) {
            profile.sessions[i] = snapshot
        } else if !snapshot.attempts.isEmpty || snapshot.activeSeconds > 0 {
            profile.sessions.append(snapshot)
        }
        store.update(profile)
    }

    /// Earlier skills to review: due ones first, then the weakest.
    static func reviewSkills(count: Int, excluding: Set<String>, graph: SkillGraph,
                             profile: Profile, curriculumId: String) -> [String] {
        guard count > 0 else { return [] }
        let practiced = graph.ordered.filter {
            !excluding.contains($0.id) && $0.hasPractice && profile.state($0.id, in: curriculumId).attempts > 0
        }
        let due = practiced.filter { SpacedReview.isDue(profile.state($0.id, in: curriculumId)) }
        let weakest = practiced.sorted {
            profile.state($0.id, in: curriculumId).comprehension < profile.state($1.id, in: curriculumId).comprehension
        }
        var picks: [String] = []
        for s in due + weakest where !picks.contains(s.id) {
            picks.append(s.id)
            if picks.count == count { break }
        }
        return picks
    }
}
