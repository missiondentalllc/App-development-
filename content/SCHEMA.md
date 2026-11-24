# Content format

Each curriculum is one JSON file: `content/<name>/curriculum.json`.

```json
{
  "id": "math-ladder",
  "title": "Math Ladder",
  "version": 1,
  "glossary": [
    { "term": "lcm", "meaning": "least common multiple: the smallest number both numbers divide into" }
  ],
  "stages": [
    { "id": "g1", "title": "Grade 1", "order": 1, "level": "Elementary", "description": "…",
      "approaches": { "show": "…", "together": "…", "alone": "…" } }
  ],
  "skills": [
    {
      "id": "g1-add10",
      "stage": "g1",
      "part": 1,
      "title": "Addition facts to 10",
      "summary": "One line shown in lists.",
      "prerequisites": ["g1-count"],
      "lesson": {
        "explanation": "Shown before practice and after every miss.",
        "example": "6 + 3 = 9",
        "tutorSteps": ["Optional steps for the tutor"],
        "approaches": {
          "show": "Line up 6 crayons and 3 more. Count on from 6 while touching each: 7, 8, 9.",
          "together": "Do 5 + 4 together. Start at 5 and count on 4 fingers together: 6, 7, 8, 9.",
          "alone": "They solve 7 + 2 alone. Hint only if stuck: start at 7 and count on 2."
        }
      },
      "practice": { "generator": "add", "params": { "max": 5 } },
      "reinforcement": "Optional: where this skill gets reused later.",
      "sightPaceSeconds": 3,
      "day": 9,
      "subject": "Math"
    }
  ]
}
```

`day` and `subject` are only used by the First Grade plan.

## Parts of a level

Every level is split into three parts, and every skill says which one it is in with `"part"`:
**1 Foundations**, **2 Building**, **3 Mastery** (the first, middle and last third of the level in
teaching order).

## Three teaching approaches

Every level and every skill has `approaches` with three short, specific instructions for the tutor:

- **show**: the tutor shows it while the learner watches.
- **together**: tutor and learner do one specific problem together, taking turns.
- **alone**: the learner tries one problem alone; the tutor gives one hint only if stuck.

The apps show all three until the skill (or every skill in the level) is 100% mastered (sight-level).
After each miss, practice shows the next approach in order: Show, then Do together, then Try alone.

## Difficulty tiers

Every skill is practiced at three tiers: **1 Starter**, **2 Core**, **3 Challenge** (the full skill as
the lesson states it). Learners start at Starter, move up a tier after 2 right answers in a row, and
move down after 2 misses in a row. A skill only counts as Mastered or Sight-level at the Challenge tier.

- Hand-written items carry `"tier": 1 | 2 | 3`, with at least one item (ideally two or more) per tier.
- Generators scale themselves: Starter and Core shrink size settings like `max` (to about 40% and 70%),
  and Challenge uses the skill's own settings. Some generators also change shape (Starter money uses
  only dimes and pennies; Starter time uses only o'clock).

## Practice

A skill needs **either** a generator **or** hand-written items (or both; the generator wins).

**Hand-written items**

```json
"items": [
  { "prompt": "Free answer question", "answer": "42", "why": "6 groups of 7 make 42." },
  { "prompt": "Multiple choice", "choices": ["right", "wrong"], "answer": "right" },
  { "prompt": "Read aloud: cat, map, sad", "mode": "tutor", "tier": 1 }
]
```

- Every item has a `why`: one or two sentences explaining the reasoning, shown after the learner
  answers, right or wrong. For tutor-judged items it says what a correct response looks or sounds like.
  Generated questions build their own explanation from the numbers in the question.
- Answers are matched loosely: spaces and capitals are ignored, and equal numbers match (`1/2` = `0.5` = `2/4`).
- `"mode": "tutor"` shows **Correct / Not yet** buttons for the tutor (reading aloud, handwriting).
- Choices are shuffled on screen.

**Generators** (endless questions; optional `params` in brackets)

| Area | Keys |
|---|---|
| Counting | `count` (max), `countBy` (step, max), `numberAfter` (max), `compare` (max), `placeValue` (digits), `tenMore` (max), `evenOdd` (max), `roundTen` (max) |
| Add/subtract | `add` (max), `add3` (max), `sub` (max), `missingAddend` (max), `makeTen`, `doubles` (max), `factFamily` (max), `wordAdd` (max), `money`, `time` |
| Multiply/divide, fractions | `mul` (min, max), `div` (max), `orderOps`, `fractionOf` (maxDen), `fractionAdd` (maxDen), `fractionCompare`, `decimalAdd`, `percent` |
| Integers, powers | `integerAdd` (max), `integerMul` (max), `exponent` (maxBase), `sqrt` (max) |
| Algebra | `linearEq` (max), `proportion`, `slope`, `evalPoly`, `quadraticRoots` |
| Statistics | `mean`, `median`, `probabilityDie`, `binomial` (max) |
| Number theory, algebra | `gcd` (max), `lcm` (max), `mod` (max), `modInverse`, `eulerPhi`, `groupOrder` |
| Calculus | `logBase`, `derivative`, `integral`, `limit`, `geometricSeries` |
| Linear algebra, complex | `det2`, `dot`, `eigenTriangular`, `complexModulus` |

Generators are defined in `packages/TutorCore/Sources/TutorCore/Questions/Generators.swift`.

## Abbreviations

Every abbreviation or acronym (LCM, SD, sin, d/dx, CVC…) must have a plain-English meaning in the
curriculum's `glossary`. The apps show "What the short forms mean" under any lesson, question or answer
that uses one, including generated questions. Skill titles shown in lists should spell the name out,
e.g. "Diagonalization and SVD (singular value decomposition)".

## Rules the validator enforces

- Unique skill ids; every stage and prerequisite exists; no prerequisite loops.
- Multiple-choice answers appear among the choices; auto-graded items have an answer.
- Generator keys exist in `Generators.swift`.
- Every skill has a part (1–3); every level and skill has show, together and alone approaches.
- Hand-written questions have a tier (1–3), and every tier has at least one question.
- Every hand-written question has a `why` explanation.
- Every abbreviation used in lessons, questions or generated questions has a glossary meaning.
- Day-based plans run 1..N, and every prerequisite is taught on an earlier day.
