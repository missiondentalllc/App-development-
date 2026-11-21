import Foundation

/// Makes the next question for a skill: generated if the skill has a generator,
/// otherwise one of its hand-written items (avoiding immediate repeats).
public final class QuestionFactory {
    private let dice: Dice
    private var recentPrompts: [String: [String]] = [:]

    public init(dice: Dice = Dice()) { self.dice = dice }

    public func question(for skill: Skill) -> Question? {
        if let key = skill.practice.generator,
           let q = QuestionGenerators.make(key, params: skill.practice.params ?? [:], skillId: skill.id, dice: dice) {
            return q
        }
        guard let items = skill.practice.items, !items.isEmpty else { return nil }
        let recent = recentPrompts[skill.id] ?? []
        let fresh = items.filter { !recent.contains($0.prompt) }
        let item = dice.pick(fresh.isEmpty ? items : fresh)
        var updated = recent + [item.prompt]
        if updated.count > max(1, items.count - 1) { updated.removeFirst() }
        recentPrompts[skill.id] = updated

        let tutor = item.mode == "tutor"
        return Question(skillId: skill.id,
                        prompt: item.prompt,
                        choices: item.choices.map { dice.shuffled($0) },
                        answer: item.answer,
                        tutorJudged: tutor)
    }
}
