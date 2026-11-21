import Foundation

/// Placement test. Walks the stages in order, asking a few questions from each.
/// A stage passes when most answers are right at a reasonable pace; passed stages
/// are marked provisionally passing so the learner starts at the right level.
/// Practice later confirms or corrects every provisional score.
public final class Diagnostic {
    public let graph: SkillGraph
    public let questionsPerStage: Int
    public private(set) var stageIndex = 0
    public private(set) var finished = false
    public private(set) var passedStages: [String] = []
    private var stageResults: [Bool] = []
    private var stageQueue: [Skill] = []
    private let stages: [Stage]

    public init(graph: SkillGraph, questionsPerStage: Int = 4) {
        self.graph = graph
        self.questionsPerStage = questionsPerStage
        self.stages = graph.curriculum.stages.sorted { $0.order < $1.order }
        loadStage()
    }

    public var currentStage: Stage? { stageIndex < stages.count ? stages[stageIndex] : nil }

    /// Next skill to test, or nil when the test is over.
    public func nextSkill() -> Skill? {
        // Stages without questions yet are skipped (not marked passed).
        while !finished && stageQueue.isEmpty { skipStage() }
        guard !finished else { return nil }
        return stageQueue[stageResults.count % stageQueue.count]
    }

    private func skipStage() {
        stageIndex += 1
        if stageIndex >= stages.count { finished = true } else { loadStage() }
    }

    /// Record an answer. Right within 3× sight pace counts as a pass for placement.
    public func record(skill: Skill, correct: Bool, seconds: Double) {
        let pace = skill.sightPaceSeconds ?? Comprehension.defaultSightPace
        stageResults.append(correct && seconds <= pace * 3)
        if stageResults.count >= questionsPerStage {
            let passes = stageResults.filter { $0 }.count
            advance(passed: Double(passes) / Double(questionsPerStage) >= 0.75)
        }
    }

    /// Apply the result to a learner's states. Only touches skills never practiced.
    public func apply(to states: [String: SkillState]) -> [String: SkillState] {
        var out = states
        for stageId in passedStages {
            for skill in graph.curriculum.skills(in: stageId) {
                var s = out[skill.id] ?? SkillState()
                guard s.attempts == 0 else { continue }
                s.comprehension = Comprehension.masteryThreshold
                s.provisional = true
                out[skill.id] = s
            }
        }
        return out
    }

    private func advance(passed: Bool) {
        if passed, let stage = currentStage {
            passedStages.append(stage.id)
            stageIndex += 1
            if stageIndex >= stages.count { finished = true } else { loadStage() }
        } else {
            finished = true
        }
    }

    private func loadStage() {
        stageResults = []
        guard let stage = currentStage else { finished = true; return }
        // Prefer skills with generated questions, spread across the stage.
        let skills = graph.curriculum.skills(in: stage.id).filter { $0.hasPractice }
        let generated = skills.filter { $0.practice.generator != nil }
        let pool = generated.isEmpty ? skills : generated
        if pool.count <= questionsPerStage {
            stageQueue = pool
        } else {
            let step = Double(pool.count) / Double(questionsPerStage)
            stageQueue = (0..<questionsPerStage).map { pool[Int(Double($0) * step)] }
        }
    }
}
