import XCTest
@testable import TutorCore

final class ComprehensionTests: XCTestCase {
    func testFastRightBeatsSlowRight() {
        let fast = Comprehension.answerScore(correct: true, seconds: 2, sightPace: 5)
        let slow = Comprehension.answerScore(correct: true, seconds: 50, sightPace: 5)
        XCTAssertEqual(fast, 1.0, accuracy: 0.001)
        XCTAssertLessThan(slow, 0.6)
        XCTAssertEqual(Comprehension.answerScore(correct: false, seconds: 1, sightPace: 5), 0)
    }

    func testMasteryNeedsEnoughAttempts() {
        var s = SkillState()
        for _ in 0..<4 { s = Comprehension.record(s, correct: true, seconds: 2, sightPace: 5) }
        XCTAssertEqual(Comprehension.level(s), .passing)
        s = Comprehension.record(s, correct: true, seconds: 2, sightPace: 5)
        XCTAssertEqual(Comprehension.level(s), .sight)
    }

    func testMissResetsReviewBox() {
        var s = SkillState()
        s = Comprehension.record(s, correct: true, seconds: 1, sightPace: 5)
        s = Comprehension.record(s, correct: true, seconds: 1, sightPace: 5)
        XCTAssertEqual(s.reviewBox, 2)
        s = Comprehension.record(s, correct: false, seconds: 1, sightPace: 5)
        XCTAssertEqual(s.reviewBox, 0)
    }
}

final class AnswerCheckerTests: XCTestCase {
    func testEquivalentNumbers() {
        XCTAssertTrue(AnswerChecker.matches("1/2", "0.5"))
        XCTAssertTrue(AnswerChecker.matches(" 07 ", "7"))
        XCTAssertTrue(AnswerChecker.matches("6/8", "3/4"))
        XCTAssertTrue(AnswerChecker.matches("3:30", "3:30"))
        XCTAssertTrue(AnswerChecker.matches("Even", "even"))
        XCTAssertFalse(AnswerChecker.matches("8", "7"))
    }
}

final class GeneratorTests: XCTestCase {
    static let keys = ["count", "countBy", "numberAfter", "compare", "placeValue", "tenMore", "evenOdd",
                       "roundTen", "add", "add3", "sub", "missingAddend", "makeTen", "doubles", "factFamily",
                       "wordAdd", "money", "time", "mul", "div", "orderOps", "fractionOf", "fractionAdd",
                       "fractionCompare", "decimalAdd", "percent", "integerAdd", "integerMul", "exponent",
                       "sqrt", "linearEq", "proportion", "slope", "evalPoly", "quadraticRoots", "mean",
                       "median", "probabilityDie", "binomial", "gcd", "lcm", "mod", "modInverse",
                       "eulerPhi", "groupOrder", "logBase", "derivative", "integral", "limit",
                       "geometricSeries", "det2", "dot", "eigenTriangular", "complexModulus"]

    func testEveryGeneratorMakesAnswerableQuestions() {
        let dice = Dice(seed: 42)
        for key in Self.keys {
            for _ in 0..<200 {
                guard let q = QuestionGenerators.make(key, skillId: "t", dice: dice) else {
                    return XCTFail("No generator for \(key)")
                }
                XCTAssertFalse(q.prompt.isEmpty, key)
                let answer = try! XCTUnwrap(q.answer, key)
                XCTAssertTrue(q.check(answer), "\(key): \(q.prompt) -> \(answer)")
                if let choices = q.choices { XCTAssertTrue(choices.contains(answer), "\(key) choices") }
            }
        }
    }

    func testSubtractionNeverNegative() {
        let dice = Dice(seed: 7)
        for _ in 0..<500 {
            let q = QuestionGenerators.make("sub", params: ["max": 20], skillId: "t", dice: dice)!
            XCTAssertGreaterThanOrEqual(Int(q.answer!)!, 0)
        }
    }
}

final class PickerTests: XCTestCase {
    func makeCurriculum() -> Curriculum {
        func skill(_ id: String, _ prereqs: [String]) -> Skill {
            Skill(id: id, stage: "s1", title: id, summary: "", prerequisites: prereqs,
                  lesson: Lesson(explanation: "", example: nil, tutorSteps: nil),
                  practice: Practice(generator: "add", params: nil, items: nil),
                  reinforcement: nil, day: nil, subject: nil, sightPaceSeconds: nil)
        }
        return Curriculum(id: "c", title: "c", version: 1,
                          stages: [Stage(id: "s1", title: "S1", order: 1, level: nil, description: nil)],
                          skills: [skill("a", []), skill("b", ["a"]), skill("c", ["b"])])
    }

    func testStartsAtTheBeginning() {
        let picker = SkillPicker(graph: SkillGraph(makeCurriculum()))
        XCTAssertEqual(picker.next(states: [:]).skill?.id, "a")
    }

    func testRepairsTheDeepestWeakPrerequisite() {
        let picker = SkillPicker(graph: SkillGraph(makeCurriculum()))
        var weak = SkillState(); weak.attempts = 5; weak.comprehension = 0.3
        let pick = picker.next(states: ["a": weak, "b": weak, "c": weak])
        XCTAssertEqual(pick.reason, .repair)
        XCTAssertEqual(pick.skill?.id, "a")
    }
}
