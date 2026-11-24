# App Development — Mission Dental LLC

Learning apps for iPhone and iPad, built on one shared engine.

| App | What it does | Status |
|---|---|---|
| **First Grade Tutor** | A full first-grade year in 110 daily lessons (math, reading, writing, science, social studies). Built for a parent or hired tutor to run one lesson a day. | v0.1 — content complete, app screens built, not yet compiled |
| **Math Ladder** | Adaptive math from first-grade counting through doctoral research topics (33 levels, 207 skills). Finds the biggest gaps and fixes them first. | v0.1 — full skill map, app screens built, not yet compiled |

## Web versions (no Mac, no App Store)

Both apps also run in any phone or computer browser. Each one is a single `.html` file with every lesson inside, so it works offline and can be shared by link.

| File | App |
|---|---|
| `docs/first-grade-tutor.html` | First Grade Tutor — https://missiondentalllc.github.io/App-development-/first-grade-tutor.html |
| `docs/math-ladder.html` | Math Ladder — https://missiondentalllc.github.io/App-development-/math-ladder.html |

- **Share it:** GitHub Pages serves the `docs/` folder (Settings → Pages → Deploy from a branch → `/docs`). Text the link. On the phone, open the link, then Share → **Add to Home Screen** so it opens like an app.
- **Progress** is saved in that phone's browser, per learner. Use **Back up or restore progress** on the Learners screen to copy it to another device.
- **Rebuild after editing content or code:** `python3 tools/build_web.py` (source is in `web/src/`).

## How the learning works

Both apps share the same rules (in `packages/TutorCore`):

- **Speed counts.** Every question is timed and capped at 60 seconds. Right *and* fast (at "sight pace") scores about twice as high as right-but-slow. Wrong scores zero.
- **Comprehension per skill.** Each skill gets a 0–100% score from recent answers. 70% unlocks what builds on it, 85% is mastered, 95% is sight-level.
- **Biggest holes first.** If a learner is weak on something, the engine walks back through its prerequisites to the most basic weak skill and repairs that first, starting with gaps that the most later material depends on.
- **Memory reinforcement.** Skills come back for review at growing gaps (1, 2, 4, 8, 16, 32, 64 days). A miss resets the gap.
- **Three parts per level.** Every level is split into Part 1 Foundations, Part 2 Building and Part 3 Mastery, each with its own progress and practice button.
- **Three difficulty tiers per skill.** Starter, Core and Challenge. Two right in a row moves up a tier; two misses in a row moves down. A skill only counts as mastered at the Challenge tier.
- **Three teaching approaches.** Every level and skill that isn't 100% mastered shows three ways to teach it: Show (tutor demonstrates), Do together (take turns on one problem), Try alone (one hint only if stuck).
- **Skip skills.** During practice, **Skip** sets the current skill aside for the rest of the session without scoring it. On a skill's page, **Skip this skill** takes it out of practice and review for good and keeps the skills that build on it open (undo any time). First Grade also has **Skip this day**.
- **Writing pad.** Writing questions use lined paper like a first-grade worksheet (top line, dashed middle line, baseline). Short answers (a letter, a spelling word, a plural) are written one letter per box and checked against model letters, catching b/d/p/q reversals; the app shows what it read and the tutor can mark it right if it misread. Spelling words can be read aloud by the app. Sentences and stories are written on the pad and marked by the tutor.
- **Lesson after a miss.** A wrong answer shows that skill's short lesson before the next question, plus the next teaching approach in order.
- **Profiles per child.** Each learner has separate progress.
- **Timed, pausable sessions.** Study time is timestamped and pauses are subtracted, so you can take it off screen time. Partial sessions still count. Progress can be exported to Google Drive or Files from the learner list.
- **Placement test** (Math Ladder). Climbs level by level and stops where it gets hard.

## Folder layout

```
apps/
  FirstGradeTutor/        iOS app (SwiftUI) + project.yml for XcodeGen
  MathLadder/             iOS app (SwiftUI) + project.yml for XcodeGen
web/
  src/                    Web version: engine.js (port of TutorCore), app.js (screens), style.css
packages/
  TutorCore/              Shared Swift package: models, scoring, skill picker,
                          spaced review, placement test, question generators,
                          storage, shared screens, unit tests
content/
  SCHEMA.md               How lesson files are written
  first-grade/            110-day first-grade curriculum (JSON)
  handwriting/            Model letter shapes for checking handwriting (a–z, A–Z, 0–9)
  math-ladder/            Grade 1 → doctoral math skill map (JSON)
tools/
  validate_content.py     Checks content before it ships
  build_web.py            Builds the single-file web apps into docs/
  make_handwriting_templates.py  Builds the model letters used to check handwriting
docs/
  *.html                  Built web apps (served by GitHub Pages)
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
