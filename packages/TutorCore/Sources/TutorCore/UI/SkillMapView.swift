#if canImport(SwiftUI)
import SwiftUI

/// Skill map: every stage and skill, colored by how well the learner knows it.
public struct SkillMapView: View {
    let curriculum: Curriculum
    let profile: Profile
    var groupBySubject = false

    public init(curriculum: Curriculum, profile: Profile, groupBySubject: Bool = false) {
        self.curriculum = curriculum
        self.profile = profile
        self.groupBySubject = groupBySubject
    }

    public var body: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.skills) { skill in
                        NavigationLink {
                            ScrollView { LessonCard(skill: skill, curriculum: curriculum).padding() }
                                .navigationTitle(skill.title)
                        } label: {
                            row(skill)
                        }
                    }
                } header: {
                    HStack {
                        Text(section.title)
                        Spacer()
                        Text("\(section.mastered)/\(section.skills.count) mastered")
                    }
                }
            }
        }
        .navigationTitle("Skill map")
    }

    private func row(_ skill: Skill) -> some View {
        let state = profile.state(skill.id, in: curriculum.id)
        let level = Comprehension.level(state)
        return HStack {
            Circle().fill(level.color).frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(skill.title)
                Text(level.label + (state.provisional ? " (from placement)" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !skill.hasPractice {
                Text("coming soon").font(.caption2).foregroundStyle(.secondary)
            } else if state.attempts > 0 || state.provisional {
                Text("\(Int(state.comprehension * 100))%").monospacedDigit()
            }
        }
    }

    private struct SectionData {
        let title: String
        let skills: [Skill]
        let mastered: Int
    }

    private var sections: [SectionData] {
        let states = profile.progress[curriculum.id] ?? [:]
        func count(_ skills: [Skill]) -> Int {
            skills.filter {
                let l = Comprehension.level(states[$0.id] ?? SkillState())
                return l == .mastered || l == .sight
            }.count
        }
        if groupBySubject {
            let subjects = Array(Set(curriculum.skills.compactMap { $0.subject })).sorted()
            return subjects.map { subject in
                let skills = curriculum.skills.filter { $0.subject == subject }.sorted { ($0.day ?? 0) < ($1.day ?? 0) }
                return SectionData(title: subject, skills: skills, mastered: count(skills))
            }
        }
        return curriculum.stages.sorted { $0.order < $1.order }.map { stage in
            let skills = curriculum.skills(in: stage.id)
            return SectionData(title: stage.title, skills: skills, mastered: count(skills))
        }
    }
}

public extension Comprehension.Level {
    var color: Color {
        switch self {
        case .new: return .gray.opacity(0.4)
        case .learning: return .orange
        case .passing: return .yellow
        case .mastered: return .green
        case .sight: return .blue
        }
    }
}

/// Pick or add a learner.
public struct ProfilePickerView: View {
    @ObservedObject var store: ProfileStore
    var onSelect: (Profile) -> Void
    @State private var newName = ""

    public init(store: ProfileStore, onSelect: @escaping (Profile) -> Void) {
        self.store = store
        self.onSelect = onSelect
    }

    public var body: some View {
        List {
            Section("Who's learning?") {
                ForEach(store.profiles) { p in
                    Button {
                        onSelect(p)
                    } label: {
                        HStack {
                            Text(p.name).font(.title3)
                            Spacer()
                            Text("\(Int(p.studySeconds(on: Date()) / 60)) min today")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in idx.map { store.profiles[$0].id }.forEach(store.delete) }
            }
            Section("Add a learner") {
                HStack {
                    TextField("Name", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        store.add(name: name)
                        newName = ""
                    }
                }
            }
            if let url = store.exportURL(), !store.profiles.isEmpty {
                Section {
                    ShareLink("Export progress (save to Drive or Files)", item: url)
                }
            }
        }
    }
}
#endif
