import Foundation

/// Makes the next question for a skill: generated if the skill has a generator,
/// otherwise one of its hand-written items (avoiding immediate repeats).
public final class QuestionFactory {
    private let dice: Dice
    private var recentPrompts: [String: [String]] = [:]

    public init(dice: Dice = Dice()) { self.dice = dice }

    public func question(for skill: Skill, tier: Int = 3) -> Question? {
        if let key = skill.practice.generator,
           var q = QuestionGenerators.make(key, params: QuestionGenerators.tierParams(key, skill.practice.params ?? [:], tier: tier),
                                           skillId: skill.id, dice: dice, tier: tier) {
            q.tier = tier
            return q
        }
        guard let all = skill.practice.items, !all.isEmpty else { return nil }
        // Items for this tier; if none, the closest tier (easier first). Untagged items fit any tier.
        var items: [Item] = []
        for t in [tier, tier - 1, tier + 1, tier - 2, tier + 2] {
            items = all.filter { $0.tier == nil || $0.tier == t }
            if !items.isEmpty { break }
        }
        let recent = recentPrompts[skill.id] ?? []
        let fresh = items.filter { !recent.contains($0.prompt) }
        let item = dice.pick(fresh.isEmpty ? items : fresh)
        var updated = recent + [item.prompt]
        if updated.count > max(1, items.count - 1) { updated.removeFirst() }
        recentPrompts[skill.id] = updated

        let tutor = item.mode == "tutor"
        var q = Question(skillId: skill.id,
                         prompt: item.prompt,
                         choices: item.choices.map { dice.shuffled($0) },
                         answer: item.answer,
                         tutorJudged: tutor)
        q.tier = tier
        q.why = item.why
        return q
    }
}
