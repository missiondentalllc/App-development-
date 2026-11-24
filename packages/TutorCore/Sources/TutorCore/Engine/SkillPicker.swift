import Foundation

/// Decides what the learner works on next.
///
/// Order of business ("biggest holes first"):
/// 1. Repair: a skill the learner has tried and is weak on, weighted by how much
///    later material depends on it. If one of its prerequisites is also weak,
///    go back and fix that first (academic therapy).
/// 2. Review: a skill due for spaced review (memory reinforcement).
/// 3. Advance: the next unlocked skill not yet started.
public struct SkillPicker {
    public enum Reason: String, Codable {
        case repair, review, advance, done

        public var label: String {
            switch self {
            case .repair: return "Fixing a gap"
            case .review: return "Memory review"
            case .advance: return "New skill"
            case .done: return "All caught up"
            }
        }
    }

    public struct Pick {
        public let skill: Skill?
        public let reason: Reason
    }

    public let graph: SkillGraph

    public init(graph: SkillGraph) { self.graph = graph }

    /// `excluding`: skills to leave out (skipped for good or for this session).
    /// `skipped`: skills skipped for good; they count as done for unlocking what builds on them.
    public func next(states: [String: SkillState], now: Date = Date(), excluding: Set<String> = [],
                     skipped: Set<String> = []) -> Pick {
        let practicable = graph.ordered.filter { $0.hasPractice && !excluding.contains($0.id) }

        // 1. Repair the weakest high-impact skill.
        let weak = practicable.filter {
            let s = states[$0.id] ?? SkillState()
            return s.attempts >= 3 && !s.provisional && s.comprehension < Comprehension.passThreshold
        }
        if let worst = weak.max(by: { priority($0, states) < priority($1, states) }) {
            return Pick(skill: deepestWeakRoot(of: worst, states: states, excluding: excluding), reason: .repair)
        }

        // 2. Spaced review that is due, oldest first.
        let due = practicable
            .filter { SpacedReview.isDue(states[$0.id] ?? SkillState(), now: now) }
            .sorted { (states[$0.id]?.nextReview ?? now) < (states[$1.id]?.nextReview ?? now) }
        if let first = due.first { return Pick(skill: first, reason: .review) }

        // 3. Keep working on an unlocked skill that isn't mastered, else start a new one.
        let unlocked = practicable.filter { graph.isUnlocked($0, states: states, skipped: skipped) }
        if let inProgress = unlocked.first(where: {
            let s = states[$0.id] ?? SkillState()
            let level = Comprehension.level(s)
            return s.attempts > 0 && (level == .learning || level == .passing)
        }) {
            return Pick(skill: inProgress, reason: .advance)
        }
        if let fresh = unlocked.first(where: { Comprehension.level(states[$0.id] ?? SkillState()) == .new }) {
            return Pick(skill: fresh, reason: .advance)
        }
        return Pick(skill: nil, reason: .done)
    }

    private func priority(_ skill: Skill, _ states: [String: SkillState]) -> Double {
        let s = states[skill.id] ?? SkillState()
        return Double((graph.impact[skill.id] ?? 0) + 1) * (1 - s.comprehension)
    }

    /// Walk down to the most basic weak prerequisite that has practice.
    private func deepestWeakRoot(of skill: Skill, states: [String: SkillState], excluding: Set<String>) -> Skill {
        var current = skill
        var visited = Set<String>()
        while visited.insert(current.id).inserted {
            let weakPrereq = current.prerequisites
                .compactMap { graph.skill($0) }
                .filter { $0.hasPractice && !excluding.contains($0.id) }
                .first {
                    let s = states[$0.id] ?? SkillState()
                    return s.attempts > 0 && s.comprehension < Comprehension.passThreshold
                }
            guard let w = weakPrereq else { break }
            current = w
        }
        return current
    }
}
