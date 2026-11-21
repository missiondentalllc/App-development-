import SwiftUI
import TutorCore

/// All levels from Grade 1 to doctoral topics.
struct StageListView: View {
    @EnvironmentObject var store: ProfileStore
    let curriculum: Curriculum
    let profileId: UUID

    var body: some View {
        let profile = store.profile(profileId) ?? Profile(name: "?")
        let levels = orderedLevels
        List {
            ForEach(levels, id: \.self) { level in
                Section(level) {
                    ForEach(curriculum.stages.filter { $0.level == level }.sorted { $0.order < $1.order }) { stage in
                        NavigationLink {
                            StageDetailView(curriculum: curriculum, profileId: profileId, stage: stage)
                        } label: {
                            stageRow(stage, profile: profile)
                        }
                    }
                }
            }
        }
        .navigationTitle("The ladder")
    }

    private var orderedLevels: [String] {
        var seen: [String] = []
        for s in curriculum.stages.sorted(by: { $0.order < $1.order }) {
            let level = s.level ?? "Other"
            if !seen.contains(level) { seen.append(level) }
        }
        return seen
    }

    private func stageRow(_ stage: Stage, profile: Profile) -> some View {
        let skills = curriculum.skills(in: stage.id)
        let passed = skills.filter { Comprehension.isPassed(profile.state($0.id, in: curriculum.id)) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stage.title).font(.headline)
                Spacer()
                Text("\(passed)/\(skills.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            if let d = stage.description { Text(d).font(.caption).foregroundStyle(.secondary) }
            ProgressView(value: Double(passed), total: Double(max(skills.count, 1)))
        }
    }
}

/// One level's skills with a button to practice the whole level.
struct StageDetailView: View {
    @EnvironmentObject var store: ProfileStore
    let curriculum: Curriculum
    let profileId: UUID
    let stage: Stage

    var body: some View {
        let profile = store.profile(profileId) ?? Profile(name: "?")
        let skills = curriculum.skills(in: stage.id)
        List {
            Section {
                NavigationLink("Practice this level") {
                    SessionScreen(curriculum: curriculum, profileId: profileId,
                                  mode: .focus(skillIds: skills.map(\.id), reviewCount: 3),
                                  title: stage.title, goal: max(skills.count * 2, 12))
                }
                .font(.headline)
            }
            Section("Skills") {
                ForEach(skills) { skill in
                    let state = profile.state(skill.id, in: curriculum.id)
                    let level = Comprehension.level(state)
                    NavigationLink {
                        SkillDetailView(curriculum: curriculum, profileId: profileId, skill: skill)
                    } label: {
                        HStack {
                            Circle().fill(level.color).frame(width: 10, height: 10)
                            Text(skill.title)
                            Spacer()
                            Text(level.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(stage.title)
    }
}

/// Lesson for one skill, what it builds on, and focused practice.
struct SkillDetailView: View {
    @EnvironmentObject var store: ProfileStore
    let curriculum: Curriculum
    let profileId: UUID
    let skill: Skill

    var body: some View {
        let profile = store.profile(profileId) ?? Profile(name: "?")
        let state = profile.state(skill.id, in: curriculum.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LessonCard(skill: skill)
                HStack {
                    Circle().fill(Comprehension.level(state).color).frame(width: 12, height: 12)
                    Text(Comprehension.level(state).label)
                    if state.attempts > 0 {
                        Text("· \(Int(state.comprehension * 100))% · \(state.attempts) answered")
                    }
                }
                .font(.callout)
                let prereqs = skill.prerequisites.compactMap { curriculum.skill($0) }
                if !prereqs.isEmpty {
                    Text("Builds on").font(.headline)
                    ForEach(prereqs) { p in
                        NavigationLink(p.title) {
                            SkillDetailView(curriculum: curriculum, profileId: profileId, skill: p)
                        }
                    }
                }
                NavigationLink {
                    SessionScreen(curriculum: curriculum, profileId: profileId,
                                  mode: .focus(skillIds: [skill.id], reviewCount: 2),
                                  title: skill.title, goal: 10)
                } label: {
                    Text("Practice this skill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle(skill.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
