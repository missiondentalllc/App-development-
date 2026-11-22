#if canImport(SwiftUI)
import SwiftUI
import Combine

/// The question screen shared by both apps.
public struct PracticeView: View {
    @ObservedObject var session: PracticeSession
    var onDone: () -> Void
    @State private var typed = ""
    @State private var now = Date()
    private let tick = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    public init(session: PracticeSession, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
        }
        .padding()
        .onAppear { if session.question == nil && !session.finished { session.start() } }
        .onReceive(tick) { date in
            now = date
            if session.feedback == nil, !session.isPaused, session.question != nil,
               session.elapsed(now: date) >= Comprehension.questionCapSeconds {
                session.timeUp()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.currentSkill?.title ?? session.curriculum.title).font(.headline)
                Text(session.reason.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(min(session.answered + 1, max(session.goal, 1)))/\(session.goal)")
                .font(.subheadline.monospacedDigit())
            if !session.finished {
                Button(session.isPaused ? "Resume" : "Pause") {
                    session.isPaused ? session.resume() : session.pause()
                }
                .buttonStyle(.bordered)
                Button("End") { session.end() }.buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if session.finished {
            summary
        } else if session.isPaused {
            VStack(spacing: 12) {
                Text("Paused").font(.largeTitle.bold())
                Text("The clock is stopped. Progress so far is saved.").foregroundStyle(.secondary)
                Button("Resume") { session.resume() }.buttonStyle(.borderedProminent)
            }
        } else if let fb = session.feedback {
            feedbackView(fb)
        } else if let q = session.question {
            questionView(q)
        } else {
            ProgressView()
        }
    }

    private func questionView(_ q: Question) -> some View {
        let left = max(0, Comprehension.questionCapSeconds - session.elapsed(now: now))
        return VStack(spacing: 24) {
            ProgressView(value: left, total: Comprehension.questionCapSeconds)
                .tint(left > 15 ? .green : .orange)
            Text(q.prompt)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            ShortFormsBox(entries: session.curriculum.shortForms(in: [q.prompt] + (q.choices ?? [])))
            if let choices = q.choices {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(choices, id: \.self) { choice in
                        Button(choice) { session.submit(choice) }
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 60)
                            .buttonStyle(.bordered)
                    }
                }
            } else if q.tutorJudged {
                VStack(spacing: 8) {
                    Text("Tutor: mark the answer").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Button("Not yet") { session.judge(correct: false) }
                            .buttonStyle(.bordered).tint(.orange)
                        Button("Correct") { session.judge(correct: true) }
                            .buttonStyle(.borderedProminent).tint(.green)
                    }
                    .font(.title2)
                }
            } else {
                HStack {
                    TextField("Answer", text: $typed)
                        .font(.title)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        /// "What the short forms mean": shown wherever an abbreviation appears.
public struct ShortFormsBox: View {
    public let entries: [GlossaryEntry]

    public init(entries: [GlossaryEntry]) { self.entries = entries }

    public var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What the short forms mean").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entries, id: \.term) { entry in
                    (Text(entry.term).bold() + Text("  " + entry.meaning).foregroundStyle(.secondary))
                        .font(.callout)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
    }
}
#endif
                        .onSubmit(send)
                    Button("Check", action: send).buttonStyle(.borderedProminent).font(.title2)
                }
                .frame(maxWidth: 420)
            }
        }
    }

    private func send() {
        let answer = typed.trimmingCharacters(in: .whitespaces)
        guard !answer.isEmpty else { return }
        session.submit(answer)
        typed = ""
    }

    private func feedbackView(_ fb: PracticeSession.Feedback) -> some View {
        VStack(spacing: 16) {
            Text(fb.correct ? (fb.sightPace ? "Right — at sight pace!" : "Right!") : "Not quite")
                .font(.largeTitle.bold())
                .foregroundStyle(fb.correct ? .green : .orange)
            if !fb.correct, let expected = fb.expected {
                Text("Answer: \(expected)").font(.title2)
            }
            Text(String(format: "%.1f seconds", fb.seconds)).foregroundStyle(.secondary)
            if let lesson = session.lessonToShow {
                LessonCard(skill: lesson, compact: true, curriculum: session.curriculum,
                           extraTexts: [session.question?.prompt, fb.expected])
            } else {
                ShortFormsBox(entries: session.curriculum.shortForms(in: [session.question?.prompt, fb.expected]))
            }
            Button(session.lessonToShow == nil ? "Next" : "Got it — try another") { session.next() }
                .buttonStyle(.borderedProminent)
                .font(.title2)
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            Text("Session done").font(.largeTitle.bold())
            Text("\(session.correct) of \(session.answered) right")
                .font(.title2)
            Text("Study time: \(Int(session.activeSeconds / 60)) min \(Int(session.activeSeconds) % 60) s")
                .foregroundStyle(.secondary)
            if let d = session.diagnostic {
                Text("Placed through: \(d.passedStages.last.flatMap { session.curriculum.stage($0)?.title } ?? "the start")")
            }
            Button("Done", action: onDone).buttonStyle(.borderedProminent)
        }
    }
}

/// Shows a skill's explanation, example and tutor steps.
public struct LessonCard: View {
    public let skill: Skill
    public var compact = false
    /// When given, abbreviations in the lesson are explained under it.
    public var curriculum: Curriculum?
    public var extraTexts: [String?] = []

    public init(skill: Skill, compact: Bool = false, curriculum: Curriculum? = nil, extraTexts: [String?] = []) {
        self.skill = skill
        self.compact = compact
        self.curriculum = curriculum
        self.extraTexts = extraTexts
    }

    private var lessonTexts: [String?] {
        var texts: [String?] = [skill.title, skill.lesson.explanation, skill.lesson.example]
        if !compact {
            texts += [skill.summary, skill.reinforcement] + (skill.lesson.tutorSteps ?? []).map { Optional($0) }
        }
        return texts + extraTexts
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(skill.title).font(compact ? .headline : .title2.bold())
            Text(skill.lesson.explanation)
            if let ex = skill.lesson.example {
                Text("Example: \(ex)").italic()
            }
            if !compact, let steps = skill.lesson.tutorSteps, !steps.isEmpty {
                Text("Tutor steps").font(.headline).padding(.top, 4)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                    Text("\(i + 1). \(step)")
                }
            }
            if !compact, let r = skill.reinforcement {
                Text("Keep it fresh: \(r)").font(.callout).foregroundStyle(.secondary)
            }
            if let curriculum {
                ShortFormsBox(entries: curriculum.shortForms(in: lessonTexts))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
/// "What the short forms mean": shown wherever an abbreviation appears.
public struct ShortFormsBox: View {
    public let entries: [GlossaryEntry]

    public init(entries: [GlossaryEntry]) { self.entries = entries }

    public var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What the short forms mean").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(entries, id: \.term) { entry in
                    (Text(entry.term).bold() + Text("  " + entry.meaning).foregroundStyle(.secondary))
                        .font(.callout)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
    }
}
#endif
