import Foundation

/// The prerequisite map. Used to find which skills are unlocked and how
/// much later material depends on each skill ("impact").
public struct SkillGraph {
    public let curriculum: Curriculum
    private let index: [String: Skill]
    private let dependents: [String: [String]]
    /// Number of skills that (directly or indirectly) build on each skill.
    public let impact: [String: Int]
    /// Skills in teaching order (stage order, then file order).
    public let ordered: [Skill]

    public init(_ curriculum: Curriculum) {
        self.curriculum = curriculum
        var idx: [String: Skill] = [:]
        var deps: [String: [String]] = [:]
        for s in curriculum.skills {
            idx[s.id] = s
            for p in s.prerequisites { deps[p, default: []].append(s.id) }
        }
        self.index = idx
        self.dependents = deps

        var impactMap: [String: Int] = [:]
        for s in curriculum.skills {
            var seen = Set<String>()
            var stack = deps[s.id] ?? []
            while let next = stack.popLast() {
                if seen.insert(next).inserted { stack.append(contentsOf: deps[next] ?? []) }
            }
            impactMap[s.id] = seen.count
        }
        self.impact = impactMap

        let stageOrder = Dictionary(uniqueKeysWithValues: curriculum.stages.map { ($0.id, $0.order) })
        let position = Dictionary(uniqueKeysWithValues: curriculum.skills.enumerated().map { ($1.id, $0) })
        self.ordered = curriculum.skills.sorted {
            let a = stageOrder[$0.stage] ?? 0, b = stageOrder[$1.stage] ?? 0
            if a != b { return a < b }
            if let d0 = $0.day, let d1 = $1.day, d0 != d1 { return d0 < d1 }
            return (position[$0.id] ?? 0) < (position[$1.id] ?? 0)
        }
    }

    public func skill(_ id: String) -> Skill? { index[id] }

    public func isUnlocked(_ skill: Skill, states: [String: SkillState]) -> Bool {
        skill.prerequisites.allSatisfy { Comprehension.isPassed(states[$0] ?? SkillState()) }
    }

    /// All prerequisites, direct and indirect.
    public func ancestors(of id: String) -> Set<String> {
        var seen = Set<String>()
        var stack = index[id]?.prerequisites ?? []
        while let next = stack.popLast() {
            if seen.insert(next).inserted { stack.append(contentsOf: index[next]?.prerequisites ?? []) }
        }
        return seen
    }
}
