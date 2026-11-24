import SwiftUI
import TutorCore

/// Today's lesson for one learner, plus review, skill map and day controls.
struct HomeView: View {
    @EnvironmentObject var store: ProfileStore
    let curriculum: Curriculum
    let profileId: UUID
    var onSwitchLearner: () -> Void

    private var profile: Profile { store.profile(profileId) ?? Profile(name: "?") }
    private var totalDays: Int { curriculum.skills.count }
    private var day: Int { min(max(profile.currentDay[curriculum.id] ?? 1, 1), totalDays) }
    private var todaysSkill: Skill? { curriculum.skills.first { $0.day == day } }

    var body: some View {
        List {
            Section {
                if let skill = todaysSkill {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Day \(day) of \(totalDays) · \(skill.subject ?? "") · Part \(SkillGraph(curriculum).part(of: skill)): \(Part.names[SkillGraph(curriculum).part(of: skill)] ?? "")")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(skill.title).font(.title.bold())
                        Text(skill.summary)
                        levelLine(skill)
                    }
                    .padding(.vertical, 4)
                    NavigationLink("Start today's lesson") {
                        LessonFlowView(curriculum: curriculum, profileId: profileId, skill: skill)
                    }
                    .font(.headline)
                } else {
                    Text("All 110 days complete! 🎉").font(.title2)
                }
            } header: {
                Text("Today")
            }

            if let skill = todaysSkill, let stage = curriculum.stage(skill.stage) {
                Section("This level: \(stage.title)") {
                    ForEach(SkillGraph(curriculum).parts(of: stage.id), id: \.number) { part in
                        let done = part.skills.filter {
                            let l = Comprehension.level(profile.state($0.id, in: curriculum.id))
                            return l == .mastered || l == .sight
                        }.count
                        LabeledContent("Part \(part.number) · \(part.name)", value: "\(done)/\(part.skills.count) mastered")
                    }
                    let skills = curriculum.skills(in: stage.id)
                    if let a = stage.approaches,
                       !skills.allSatisfy({ Comprehension.isFullyMastered(profile.state($0.id, in: curriculum.id)) }) {
                        DisclosureGroup("Three ways to teach this level") {
                            ApproachesList(approaches: a, heading: "")
                        }
                    }
                }
            }

            Section("Tutor controls") {
                Stepper("Day \(day)", value: dayBinding, in: 1...totalDays)
                NavigationLink("Memory review (earlier topics)") {
                    ReviewSessionView(curriculum: curriculum, profileId: profileId)
                }
                NavigationLink("Skill map") {
                    SkillMapView(curriculum: curriculum, profile: profile, groupBySubject: true)
                }
            }

            Section("Progress") {
                LabeledContent("Study time today", value: "\(Int(profile.studySeconds(on: Date()) / 60)) min")
                LabeledContent("Topics mastered", value: "\(masteredCount) of \(totalDays)")
                ProgressView(value: Double(day - 1), total: Double(totalDays))
            }
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Learners", action: onSwitchLearner)
            }
        }
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { day },
            set: { newDay in
                var p = profile
                p.currentDay[curriculum.id] = newDay
                store.update(p)
            }
        )
    }

    private var masteredCount: Int {
        curriculum.skills.filter {
            let level = Comprehension.level(profile.state($0.id, in: curriculum.id))
            return level == .mastered || level == .sight
        }.count
    }

    private func levelLine(_ skill: Skill) -> some View {
        let state = profile.state(skill.id, in: curriculum.id)
        let level = Comprehension.level(state)
        return HStack {
            Circle().fill(level.color).frame(width: 10, height: 10)
            Text(level.label)
            if state.attempts > 0 { Text("· \(Int(state.comprehension * 100))%") }
        }
        .font(.caption)
    }
}

/// Free review: earlier topics that are due or weakest.
struct ReviewSessionView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let curriculum: Curriculum
    let profileId: UUID
    @State private var session: PracticeSession?

    var body: some View {
        Group {
            if let session {
                PracticeView(session: session) { dismiss() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Memory review")
        .onAppear {
            guard session == nil, let profile = store.profile(profileId) else { return }
            session = PracticeSession(curriculum: curriculum, profile: profile, store: store,
                                      mode: .focus(skillIds: [], reviewCount: 10))
        }
        .onDisappear { if let s = session, !s.finished { s.end() } }
    }
}
