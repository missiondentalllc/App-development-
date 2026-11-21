import SwiftUI
import TutorCore

/// One day's lesson: teach → practice (with memory review at the end) → result.
struct LessonFlowView: View {
    @EnvironmentObject var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    let curriculum: Curriculum
    let profileId: UUID
    let skill: Skill

    private enum Step { case teach, practice, result }
    @State private var step: Step = .teach
    @State private var session: PracticeSession?

    var body: some View {
        Group {
            switch step {
            case .teach: teach
            case .practice:
                if let session {
                    PracticeView(session: session) { step = .result }
                }
            case .result: result
            }
        }
        .navigationTitle("Day \(skill.day ?? 0)")
        .onDisappear { if let s = session, !s.finished { s.end() } }
    }

    private var teach: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(skill.subject ?? "").font(.subheadline).foregroundStyle(.secondary)
                LessonCard(skill: skill)
                let earlier = skill.prerequisites.compactMap { curriculum.skill($0)?.title }
                if !earlier.isEmpty {
                    Text("Builds on: " + earlier.joined(separator: ", "))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button {
                    startPractice()
                } label: {
                    Text("Start practice").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    private var result: some View {
        let profile = store.profile(profileId)
        let state = profile?.state(skill.id, in: curriculum.id) ?? SkillState()
        let level = Comprehension.level(state)
        let passed = Comprehension.isPassed(state)
        let lastDay = curriculum.skills.count

        return VStack(spacing: 16) {
            Text(skill.title).font(.title2.bold())
            HStack {
                Circle().fill(level.color).frame(width: 14, height: 14)
                Text("\(level.label) · \(Int(state.comprehension * 100))%")
            }
            .font(.title3)
            if let avg = state.averageSeconds {
                Text(String(format: "Average %.1f s per question", avg)).foregroundStyle(.secondary)
            }
            Text(passed ? "Ready for the next day." : "Not passed yet — practice again tomorrow, or move on if you're sure.")
                .multilineTextAlignment(.center)

            if let day = skill.day, day < lastDay {
                Button(passed ? "Go to Day \(day + 1)" : "Move on anyway") { moveOn(to: day + 1) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Practice again") { startPractice() }.buttonStyle(.bordered)
            Button("Back to home") { dismiss() }
        }
        .padding()
    }

    private func startPractice() {
        guard let profile = store.profile(profileId) else { return }
        session = PracticeSession(curriculum: curriculum, profile: profile, store: store,
                                  mode: .focus(skillIds: [skill.id], reviewCount: 4), goal: 8)
        step = .practice
    }

    private func moveOn(to day: Int) {
        guard var profile = store.profile(profileId) else { return }
        profile.currentDay[curriculum.id] = day
        store.update(profile)
        dismiss()
    }
}
