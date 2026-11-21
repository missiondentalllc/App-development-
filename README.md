# App Development — Mission Dental LLC

Learning apps for iPhone and iPad, built on one shared engine.

| App | What it does | Status |
|---|---|---|
| **First Grade Tutor** | A full first-grade year in 110 daily lessons (math, reading, writing, science, social studies). Built for a parent or hired tutor to run one lesson a day. | v0.1 — content complete, app screens built, not yet compiled |
| **Math Ladder** | Adaptive math from first-grade counting through doctoral research topics (33 levels, 207 skills). Finds the biggest gaps and fixes them first. | v0.1 — full skill map, app screens built, not yet compiled |

## How the learning works

Both apps share the same rules (in `packages/TutorCore`):

- **Speed counts.** Every question is timed and capped at 60 seconds. Right *and* fast (at "sight pace") scores about twice as high as right-but-slow. Wrong scores zero.
- **Comprehension per skill.** Each skill gets a 0–100% score from recent answers. 70% unlocks what builds on it, 85% is mastered, 95% is sight-level.
- **Biggest holes first.** If a learner is weak on something, the engine walks back through its prerequisites to the most basic weak skill and repairs that first, starting with gaps that the most later material depends on.
- **Memory reinforcement.** Skills come back for review at growing gaps (1, 2, 4, 8, 16, 32, 64 days). A miss resets the gap.
- **Lesson after a miss.** A wrong answer shows that skill's short lesson before the next question.
- **Profiles per child.** Each learner has separate progress.
- **Timed, pausable sessions.** Study time is timestamped and pauses are subtracted, so you can take it off screen time. Partial sessions still count. Progress can be exported to Google Drive or Files from the learner list.
- **Placement test** (Math Ladder). Climbs level by level and stops where it gets hard.

## Folder layout

```
apps/
  FirstGradeTutor/        iOS app (SwiftUI) + project.yml for XcodeGen
  MathLadder/             iOS app (SwiftUI) + project.yml for XcodeGen
packages/
  TutorCore/              Shared Swift package: models, scoring, skill picker,
                          spaced review, placement test, question generators,
                          storage, shared screens, unit tests
content/
  SCHEMA.md               How lesson files are written
  first-grade/            110-day first-grade curriculum (JSON)
  math-ladder/            Grade 1 → doctoral math skill map (JSON)
tools/
  validate_content.py     Checks content before it ships
docs/
  ARCHITECTURE.md         How the pieces fit
  ROADMAP.md              What's next
```

## Building the apps (needs a Mac)

iPhone apps can only be compiled on a Mac with Xcode.

1. Install **Xcode** (free, Mac App Store) and **XcodeGen**: `brew install xcodegen`
2. Clone this repo.
3. `cd apps/FirstGradeTutor && xcodegen` (or `apps/MathLadder`)
4. Open the generated `.xcodeproj`, pick an iPhone or iPad simulator, and press Run.
5. Run the engine tests: `cd packages/TutorCore && swift test`

To publish to the App Store you also need an Apple Developer account ($99/year).

## Editing content

Lessons and questions live in plain JSON under `content/`, not in code. See `content/SCHEMA.md`.
After any change, run:

```
python3 tools/validate_content.py
```

It checks prerequisites, loops, answers, generator names and lesson order, and it fails if anything is wrong.
