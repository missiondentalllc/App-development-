# Architecture

```
content/*.json ──► ContentLoader ──► Curriculum ──► SkillGraph (prerequisites, impact)
                                                        │
                    ProfileStore (JSON on device) ◄──► PracticeSession ◄── SkillPicker / Diagnostic
                                                        │                    QuestionFactory → QuestionGenerators
                                                        ▼
                                              PracticeView / LessonCard / SkillMapView (SwiftUI)
```

## TutorCore (shared Swift package)

| File | Job |
|---|---|
| `Models/Curriculum.swift` | Curriculum, Stage, Skill, Lesson, Practice, Item (matches the JSON) |
| `Models/Profile.swift` | Learner, per-skill state, timestamped study sessions, attempts |
| `Engine/Comprehension.swift` | Scores answers by accuracy and speed; mastery levels |
| `Engine/SpacedReview.swift` | Review schedule (1 → 64 days) |
| `Engine/SkillGraph.swift` | Prerequisite map; how many skills depend on each ("impact") |
| `Engine/SkillPicker.swift` | Next skill: repair biggest gap → due review → next new skill |
| `Engine/Diagnostic.swift` | Placement test |
| `Questions/*` | Question type, lenient answer checking, generators, item picking |
| `Session/PracticeSession.swift` | Runs a session: timing, pauses, scoring, saving after every answer |
| `Storage/*` | Loading content, saving profiles, export for Google Drive / Files |
| `UI/*` | Question screen, lesson card, skill map, learner picker |

## Scoring

For each answer: wrong = 0; right = 0.5 + 0.5 × speed, where speed is 1.0 at or under the skill's sight pace and falls to 0 at the 60-second cap. A skill's comprehension is a moving average (newest answer weighted 30%).

| Level | Rule |
|---|---|
| Learning | below 70% |
| Passing | 70%+ (unlocks dependent skills) |
| Mastered | 85%+ with at least 5 answers |
| Sight-level | 95%+ with at least 5 answers |

## Apps

- **FirstGradeTutor**: home shows Day N's topic; lesson flow is teach → practice (today's topic plus memory review of earlier topics) → result → move to the next day. The tutor can change the day and run extra review.
- **MathLadder**: home shows the engine's next pick and biggest gaps; continue practice (adaptive), placement test, browse all 33 levels, practice any level or skill.

Both apps are generated from `project.yml` with XcodeGen, so no Xcode project files are committed.
