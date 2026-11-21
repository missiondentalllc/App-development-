# Content format

Each curriculum is one JSON file: `content/<name>/curriculum.json`.

```json
{
  "id": "math-ladder",
  "title": "Math Ladder",
  "version": 1,
  "stages": [
    { "id": "g1", "title": "Grade 1", "order": 1, "level": "Elementary", "description": "…" }
  ],
  "skills": [
    {
      "id": "g1-add10",
      "stage": "g1",
      "title": "Addition facts to 10",
      "summary": "One line shown in lists.",
      "prerequisites": ["g1-count"],
      "lesson": {
        "explanation": "Shown before practice and after every miss.",
        "example": "6 + 3 = 9",
        "tutorSteps": ["Optional steps for the tutor"]
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

## Practice

A skill needs **either** a generator **or** hand-written items (or both; the generator wins).

**Hand-written items**

```json
"items": [
  { "prompt": "Free answer question", "answer": "42" },
  { "prompt": "Multiple choice", "choices": ["right", "wrong"], "answer": "right" },
  { "prompt": "Read aloud: cat, map, sad", "mode": "tutor" }
]
```

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
| Number theory, algebra | `gcd`, `lcm`, `mod` (max), `modInverse`, `eulerPhi`, `groupOrder` |
| Calculus | `logBase`, `derivative`, `integral`, `limit`, `geometricSeries` |
| Linear algebra, complex | `det2`, `dot`, `eigenTriangular`, `complexModulus` |

Generators are defined in `packages/TutorCore/Sources/TutorCore/Questions/Generators.swift`.

## Rules the validator enforces

- Unique skill ids; every stage and prerequisite exists; no prerequisite loops.
- Multiple-choice answers appear among the choices; auto-graded items have an answer.
- Generator keys exist in `Generators.swift`.
- Day-based plans run 1..N, and every prerequisite is taught on an earlier day.
