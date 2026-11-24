import SwiftUI
import TutorCore

/// Home for one learner: continue adaptive practice, take the placement test,
/// browse the ladder, see what the engine thinks the biggest gaps are.
struct LadderHomeView: View {
    @EnvironmentObject var store: ProfileStore
    let curriculum: Curriculum
    let profileId: UUID
    var onSwitchLearner: () -> Void

    private var profile: Profile { store.profile(profileId) ?? Profile(name: "?") }
    private var states: [String: SkillState] { profile.progress[curriculum.id] ?? [:] }
    private var graph: SkillGraph { SkillGraph(curriculum) }

    var body: some View {
        List {
            Section {
                let skipped = profile.skippedSkills(in: curriculum.id)
                let pick = SkillPicker(graph: graph).next(states: states, excluding: skipped, skipped: skipped)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Up next · \(pick.reason.label)").font(.subheadline).foregroundStyle(.secondary)
                    Text(pick.skill?.title ?? "Everything available is mastered").font(.title2.bold())
                    if let s = pick.skill, let stage = curriculum.stage(s.stage) {
                        Text(stage.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                NavigationLink("Continue practice (20 questions)") {
                    SessionScreen(curriculum: curriculum, profileId: profileId, mode: .adaptive, title: "Practice")
                }
                .font(.headline)
            }

            Section("Placement") {
                NavigationLink("Placement test") {
                    SessionScreen(curriculum: curriculum, profileId: profileId, mode: .diagnostic, title: "Placement test")
                }
                Text("Climbs the ladder a few questions per level and stops where it gets hard. Practice later confirms or corrects the placement.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Biggest gaps") {
                let gaps = biggestGaps
                if gaps.isEmpty {
                    Text("No gaps found yet — keep practicing.").foregroundStyle(.secondary)
                }
                ForEach(gaps, id: \.id) { skill in
                    NavigationLink {
                        SkillDetailView(curriculum: curriculum, profileId: profileId, skill: skill)
                    } label: {
                        HStack {
                            Text(skill.title)
                            Spacer()
                            Text("\(Int((states[skill.id]?.comprehension ?? 0) * 100))%").monospacedDigit()
                        }
                    }
                }
            }

            Section("The ladder") {
                NavigationLink("Browse all levels") {
                    StageListView(curriculum: curriculum, profileId: profileId)
                }
                NavigationLink("Skill map") {
                    SkillMapView(curriculum: curriculum, profile: profile)
                }
                LabeledContent("Highest level reached", value: highestStage)
                LabeledContent("Skills mastered", value: "\(masteredCount) of \(curriculum.skills.count)")
            }

            Section("Time") {
                LabeledContent("Study time today", value: "\(Int(profile.studySeconds(on: Date()) / 60)) min")
                Text("Subtract this from screen time. Paused time doesn't count.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Learners", action: onSwitchLearner) }
        }
    }

    /// Weak skills that the most later material depends on.
    private var biggestGaps: [Skill] {
        let g = graph
        let skipped = profile.skippedSkills(in: curriculum.id)
        return curriculum.skills
            .filter {
                guard !skipped.contains($0.id) else { return false }
                let s = states[$0.id] ?? SkillState()
                return s.attempts >= 3 && !s.provisional && s.comprehension < Comprehension.passThreshold
            }
            .sorted {
                Double((g.impact[$0.id] ?? 0) + 1) * (1 - (states[$0.id]?.comprehension ?? 0)) >
                Double((g.impact[$1.id] ?? 0) + 1) * (1 - (states[$1.id]?.comprehension ?? 0))
            }
            .prefix(5)
            .map { $0 }
    }

    private var masteredCount: Int {
        curriculum.skills.filter {
            let l = Comprehension.level(states[$0.id] ?? SkillState())
            return l == .mastered || l == .sight
        }.count
    }

    private var highestStage: String {
        let passed = curriculum.stages.sorted { $0.order < $1.order }.last { stage in
            let skills = curriculum.skills(in: stage.id)
            return !skills.isEmpty && skills.allSatisfy { Comprehension.isPassed(states[$0.id] ?? SkillState()) }
        }
        return passed?.title ?? "Just starting"
    }
}

/// Hosts a PracticeSession for any mode.
struct SessionScreen: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let curriculum: Curriculum
    let profileId: UUID
    let mode: PracticeSession.Mode
    let title: String
    var goal = 20
    @State private var session: PracticeSession?

    var body: some View {
        Group {
            if let session {
                PracticeView(session: session) { dismiss() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard session == nil, let profile = store.profile(profileId) else { return }
            session = PracticeSession(curriculum: curriculum, profile: profile, store: store, mode: mode, goal: goal)
        }
        .onDisappear { if let s = session, !s.finished { s.end() } }
    }
}
