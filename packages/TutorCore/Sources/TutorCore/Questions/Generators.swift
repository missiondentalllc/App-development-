import Foundation

/// Random source for question generators.
public final class Dice {
    private var rng: SeededRNG
    public init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { rng = SeededRNG(seed: seed) }

    public func int(_ lo: Int, _ hi: Int) -> Int {
        lo >= hi ? lo : Int.random(in: lo...hi, using: &rng)
    }
    public func bool() -> Bool { int(0, 1) == 1 }
    public func pick<T>(_ items: [T]) -> T { items[int(0, items.count - 1)] }
    public func shuffled<T>(_ items: [T]) -> [T] { items.shuffled(using: &rng) }
}

/// Built-in generators that make endless practice questions.
/// Each `case` key below is listed in `content/SCHEMA.md`; the content
/// validator (`tools/validate_content.py`) reads this file to check that
/// every generator named in the content exists.
public enum QuestionGenerators {

    /// Size settings each generator uses, with defaults. Starter and Core shrink these;
    /// Challenge uses the skill's own settings (the full skill).
    static let sizes: [String: [String: Int]] = [
        "count": ["max": 20], "countBy": ["max": 100], "numberAfter": ["max": 120], "compare": ["max": 100],
        "placeValue": ["digits": 2], "tenMore": ["max": 100], "evenOdd": ["max": 50], "roundTen": ["max": 100],
        "add": ["max": 10], "add3": ["max": 9], "sub": ["max": 10], "missingAddend": ["max": 10], "doubles": ["max": 10],
        "factFamily": ["max": 10], "wordAdd": ["max": 10], "mul": ["max": 10], "div": ["max": 10],
        "fractionOf": ["maxDen": 10], "fractionAdd": ["maxDen": 12], "integerAdd": ["max": 20], "integerMul": ["max": 12],
        "exponent": ["maxBase": 6], "sqrt": ["max": 15], "linearEq": ["max": 10], "binomial": ["max": 10], "mod": ["max": 13],
        "gcd": ["max": 12], "lcm": ["max": 15],
    ]

    public static func tierParams(_ key: String, _ params: [String: Int], tier: Int) -> [String: Int] {
        var out = params
        guard tier < 3 else { return out }
        for (name, fallback) in sizes[key] ?? [:] {
            let full = out[name] ?? fallback
            if name == "digits" { out[name] = max(2, full - (3 - tier)); continue }
            var floor = name == "max" ? 3 : 2
            if key == "countBy" { floor = max(floor, (out["step"] ?? 1) * 4) }
            if let lo = out["min"] { floor = max(floor, lo + 1) }
            let scaled = Int((Double(full) * (tier == 1 ? 0.4 : 0.7)).rounded())
            out[name] = min(full, max(floor, scaled))
        }
        return out
    }

    public static func make(_ key: String, params: [String: Int] = [:], skillId: String, dice: Dice,
                            tier: Int = 3) -> Question? {
        func p(_ name: String, _ fallback: Int) -> Int { params[name] ?? fallback }
        // Every generated question carries `why`: a short explanation shown after any answer.
        func q(_ prompt: String, _ answer: Int, _ why: String) -> Question {
            var x = Question(skillId: skillId, prompt: prompt, answer: String(answer)); x.why = why; return x
        }
        func qs(_ prompt: String, _ answer: String, _ why: String) -> Question {
            var x = Question(skillId: skillId, prompt: prompt, answer: answer); x.why = why; return x
        }
        func mc(_ prompt: String, _ choices: [String], _ answer: String, _ why: String) -> Question {
            var x = Question(skillId: skillId, prompt: prompt, choices: choices, answer: answer); x.why = why; return x
        }
        func list(_ from: Int, _ to: Int) -> String {
            from > to ? "" : (from...to).map(String.init).joined(separator: ", ")
        }
        func countOn(_ a: Int, _ b: Int) -> String {
            if b == 0 { return "Adding 0 leaves \(a) the same." }
            if b <= 6 { return "Start at \(a) and count on \(b): \(list(a + 1, a + b))." }
            return "Make a ten or add in parts: \(a) + \(b) = \(a + b)."
        }
        func times(_ base: Int, _ n: Int) -> String { Array(repeating: String(base), count: n).joined(separator: " × ") }

        switch key {

        // MARK: Counting and number sense
        case "count":
            let n = dice.int(1, p("max", 20))
            let dots = (0..<n).map { $0 > 0 && $0 % 5 == 0 ? " ●" : "●" }.joined()
            let groups = n / 5, rest = n % 5
            let why = n > 5
                ? "The dots come in groups of 5. \(groups) group\(groups > 1 ? "s" : "") of 5 is \(groups * 5)\(rest > 0 ? ", plus \(rest) more makes \(n)" : "")."
                : "Touch each dot once and count: \(list(1, n)). The last number said is \(n)."
            return q("How many dots?\n\(dots)", n, why)
        case "countBy":
            let step = p("step", 1)
            let start = step * dice.int(0, max(0, p("max", 100) / step - 3))
            return q("What comes next?\n\(start), \(start + step), \(start + 2 * step), __", start + 3 * step,
                     "Each number is \(step) more than the one before. \(start + 2 * step) + \(step) = \(start + 3 * step).")
        case "numberAfter":
            let n = dice.int(1, p("max", 120))
            return dice.bool()
                ? q("What number comes just after \(n)?", n + 1, "Just after means 1 more: \(n) + 1 = \(n + 1).")
                : q("What number comes just before \(n)?", n - 1, "Just before means 1 less: \(n) − 1 = \(n - 1).")
        case "compare":
            let a = dice.int(0, p("max", 100))
            var b = dice.int(0, p("max", 100))
            if dice.int(0, 5) == 0 { b = a }
            let symbol = a > b ? ">" : (a < b ? "<" : "=")
            let why = a == b ? "Both numbers are \(a), so they are equal: \(a) = \(b)."
                : "\(max(a, b)) is bigger than \(min(a, b)). The open side of the sign faces the bigger number: \(a) \(symbol) \(b)."
            return mc("Which sign goes in the blank?\n\(a) __ \(b)", [">", "<", "="], symbol, why)
        case "placeValue":
            let digits = max(2, min(4, p("digits", 2)))
            let n = dice.int(Int(pow(10.0, Double(digits - 1))), Int(pow(10.0, Double(digits))) - 1)
            let places = ["ones", "tens", "hundreds", "thousands"]
            let i = dice.int(0, digits - 1)
            let digit = (n / Int(pow(10.0, Double(i)))) % 10
            let order = places.prefix(digits).reversed().joined(separator: ", ")
            return q("What digit is in the \(places[i]) place of \(n)?", digit,
                     "Reading \(n) from left to right, the places are \(order). The \(places[i]) digit is \(digit).")
        case "tenMore":
            let n = dice.int(10, max(10, p("max", 100) - 10))
            return dice.bool()
                ? q("What is 10 more than \(n)?", n + 10, "10 more changes only the tens digit, up by 1: \(n) → \(n + 10).")
                : q("What is 10 less than \(n)?", n - 10, "10 less changes only the tens digit, down by 1: \(n) → \(n - 10).")
        case "evenOdd":
            let n = dice.int(0, p("max", 50))
            let even = n % 2 == 0
            let why = "Look at the last digit, \(n % 10). " + (even
                ? "0, 2, 4, 6 and 8 make a number even: it splits into two equal groups."
                : "1, 3, 5, 7 and 9 make a number odd: one is left over when you make pairs.")
            return mc("Is \(n) even or odd?", ["Even", "Odd"], even ? "Even" : "Odd", why)
        case "roundTen":
            let n = dice.int(0, p("max", 100))
            let r = Int((Double(n) / 10).rounded(.toNearestOrAwayFromZero)) * 10, ones = n % 10
            return q("Round \(n) to the nearest ten.", r,
                     "\(n) is between \(n - ones) and \(n - ones + 10). The ones digit is \(ones), \(ones >= 5 ? "5 or more, so round up" : "less than 5, so round down") to \(r).")

        // MARK: Addition and subtraction
        case "add":
            let m = p("max", 10)
            let a = dice.int(0, m), b = dice.int(0, m)
            return q("\(a) + \(b) = ?", a + b,
                     countOn(max(a, b), min(a, b)) + (a < b && a > 0 ? " (Starting from the bigger number is faster.)" : ""))
        case "add3":
            let m = p("max", 9)
            let a = dice.int(0, m), b = dice.int(0, m), c = dice.int(0, m)
            return q("\(a) + \(b) + \(c) = ?", a + b + c, "Add two at a time: \(a) + \(b) = \(a + b), then \(a + b) + \(c) = \(a + b + c).")
        case "sub":
            let a = dice.int(0, p("max", 10)), b = dice.int(0, a)
            return q("\(a) − \(b) = ?", a - b, b == 0 ? "Taking away 0 leaves \(a)."
                     : "Start at \(b) and count up to \(a). That is \(a - b) steps, so \(a) − \(b) = \(a - b). Check: \(a - b) + \(b) = \(a).")
        case "missingAddend":
            let c = dice.int(0, p("max", 10)), a = dice.int(0, c)
            return q("\(a) + ? = \(c)", c - a, "Count up from \(a) to \(c): that is \(c - a). Check: \(a) + \(c - a) = \(c).")
        case "makeTen":
            let a = dice.int(0, 10)
            return q("\(a) + ? = 10", 10 - a, "\(a) and \(10 - a) are partners that make 10. On a ten frame, \(a) filled leaves \(10 - a) empty.")
        case "doubles":
            let n = dice.int(0, p("max", 10))
            return q("\(n) + \(n) = ?", 2 * n, "A double is the same number twice. \(n) + \(n) = \(2 * n)\(n <= 5 ? " (like \(n) fingers on each hand)" : "").")
        case "factFamily":
            let m = p("max", 10)
            let a = dice.int(1, m), b = dice.int(1, m)
            return q("If \(a) + \(b) = \(a + b), what is \(a + b) − \(b)?", a,
                     "\(a), \(b) and \(a + b) are a fact family. Taking \(b) back away from \(a + b) leaves \(a).")
        case "wordAdd":
            let m = p("max", 10)
            let a = dice.int(1, m), b = dice.int(1, m)
            let thing = dice.pick(["apples", "stickers", "blocks", "shells", "crayons"])
            if dice.bool() {
                return q("Sam has \(a) \(thing). Sam gets \(b) more. How many \(thing) now?", a + b, "\"Gets more\" means add: \(a) + \(b) = \(a + b) \(thing).")
            }
            return q("Sam has \(a + b) \(thing). Sam gives away \(b). How many \(thing) are left?", a, "\"Gives away\" means subtract: \(a + b) − \(b) = \(a) \(thing).")
        case "money":
            // Starter: dimes and pennies only. Core adds nickels. Challenge adds quarters.
            let quarters = tier >= 3 ? dice.int(0, 3) : 0, dimes = dice.int(0, 4)
            let nickels = tier >= 2 ? dice.int(0, 3) : 0, pennies = dice.int(0, 4)
            let coins: [(Int, String, String, Int)] = [(quarters, "quarter", "quarters", 25), (dimes, "dime", "dimes", 10),
                                                       (nickels, "nickel", "nickels", 5), (pennies, "penny", "pennies", 1)]
            let present = coins.filter { $0.0 > 0 }
            if present.isEmpty { return q("How many cents is 1 dime?", 10, "A dime is worth 10 cents.") }
            func name(_ c: (Int, String, String, Int)) -> String { c.0 == 1 ? "1 " + c.1 : String(c.0) + " " + c.2 }
            let total = quarters * 25 + dimes * 10 + nickels * 5 + pennies
            let steps = present.map { "\(name($0)) = \($0.0 * $0.3)¢" }.joined(separator: ", ")
            return q("How many cents?\n" + present.map(name).joined(separator: ", "), total,
                     "Count the biggest coins first. \(steps). Together that is \(total) cents.")
        case "time":
            let h = dice.int(1, 12)
            if tier == 1 || dice.bool() {
                return qs("The short hand points to \(h). The long hand points to 12. What time is it?", "\(h):00",
                          "The short hand tells the hour: \(h). The long hand on 12 means exactly on the hour, so it is \(h):00 (\(h) o'clock).")
            }
            let nextHour = h == 12 ? 1 : h + 1
            return qs("The short hand is between \(h) and \(nextHour). The long hand points to 6. What time is it?", "\(h):30",
                      "The hour is the number the short hand has passed: \(h). The long hand on 6 means half past, 30 minutes. So it is \(h):30.")

        // MARK: Multiplication, division, fractions, decimals
        case "mul":
            let a = dice.int(p("min", 0), p("max", 10)), b = dice.int(p("min", 0), p("max", 10))
            let why = a == 0 || b == 0 ? "Anything times 0 is 0."
                : "\(a) × \(b) means \(b) groups of \(a)" + (b <= 5 ? ": " + Array(repeating: String(a), count: b).joined(separator: " + ") + " = \(a * b)." : " = \(a * b).")
            return q("\(a) × \(b) = ?", a * b, why)
        case "div":
            let b = dice.int(1, p("max", 10)), quotient = dice.int(0, p("max", 10))
            return q("\(b * quotient) ÷ \(b) = ?", quotient,
                     "Think: what times \(b) makes \(b * quotient)? \(quotient) × \(b) = \(b * quotient), so \(b * quotient) ÷ \(b) = \(quotient).")
        case "orderOps":
            let a = dice.int(1, 9), b = dice.int(1, 9), c = dice.int(1, 9)
            return dice.bool()
                ? q("\(a) + \(b) × \(c) = ?", a + b * c, "Multiply before adding: \(b) × \(c) = \(b * c), then \(a) + \(b * c) = \(a + b * c).")
                : q("(\(a) + \(b)) × \(c) = ?", (a + b) * c, "Parentheses come first: \(a) + \(b) = \(a + b), then \(a + b) × \(c) = \((a + b) * c).")
        case "fractionOf":
            let d = dice.int(2, p("maxDen", 10)), n = d * dice.int(1, 10)
            return q("What is 1/\(d) of \(n)?", n / d, "1/\(d) means split into \(d) equal groups. \(n) ÷ \(d) = \(n / d).")
        case "fractionAdd":
            let d = dice.int(2, p("maxDen", 12)), a = dice.int(1, d), b = dice.int(1, d)
            return qs("\(a)/\(d) + \(b)/\(d) = ?", "\(a + b)/\(d)",
                      "The pieces are the same size (\(d)ths), so add the tops and keep the bottom: \(a) + \(b) = \(a + b), giving \(a + b)/\(d).")
        case "fractionCompare":
            let d1 = dice.int(2, 12), d2 = dice.int(2, 12)
            let n1 = dice.int(1, d1), n2 = dice.int(1, d2)
            if n1 * d2 == n2 * d1 {
                return mc("Which is greater?", ["\(n1)/\(d1)", "\(n1 + 1)/\(d1)"], "\(n1 + 1)/\(d1)",
                          "Same bottom number, so the one with more pieces is bigger: \(n1 + 1) pieces beats \(n1).")
            }
            let bigger = n1 * d2 > n2 * d1 ? "\(n1)/\(d1)" : "\(n2)/\(d2)"
            return mc("Which is greater?", ["\(n1)/\(d1)", "\(n2)/\(d2)"], bigger,
                      "Cross-multiply to compare: \(n1) × \(d2) = \(n1 * d2) and \(n2) × \(d1) = \(n2 * d1). The larger product belongs to \(bigger).")
        case "decimalAdd":
            let a = dice.int(1, 99), b = dice.int(1, 99)
            return qs("\(fmtTenths(a)) + \(fmtTenths(b)) = ?", fmtTenths(a + b),
                      "Line up the decimal points and add tenths: \(a) tenths + \(b) tenths = \(a + b) tenths = \(fmtTenths(a + b)).")
        case "percent":
            let pct = dice.pick([10, 20, 25, 50, 75]), n = 20 * dice.int(1, 10)
            return q("What is \(pct)% of \(n)?", pct * n / 100, "\(pct)% means \(pct) out of 100, which is \(pct)/100. \(n) × \(pct) ÷ 100 = \(pct * n / 100).")

        // MARK: Integers, powers, roots
        case "integerAdd":
            let m = p("max", 20)
            let a = dice.int(-m, m), b = dice.int(-m, m)
            let why = (a >= 0) == (b >= 0)
                ? "Same signs: add the sizes (\(abs(a)) + \(abs(b)) = \(abs(a) + abs(b))) and keep the sign. Answer: \(a + b)."
                : "Different signs: subtract the sizes (\(max(abs(a), abs(b))) − \(min(abs(a), abs(b))) = \(abs(a + b))) and take the sign of the bigger size. Answer: \(a + b)."
            return q("(\(a)) + (\(b)) = ?", a + b, why)
        case "integerMul":
            let m = p("max", 12)
            let a = dice.int(-m, m), b = dice.int(-m, m)
            let why = a == 0 || b == 0 ? "Anything times 0 is 0."
                : "\(abs(a)) × \(abs(b)) = \(abs(a * b)). \((a < 0) == (b < 0) ? "Same signs give a positive answer" : "Different signs give a negative answer"): \(a * b)."
            return q("(\(a)) × (\(b)) = ?", a * b, why)
        case "exponent":
            let base = dice.int(2, p("maxBase", 6)), e = dice.int(2, base <= 3 ? 5 : 3)
            let value = Int(pow(Double(base), Double(e)))
            return q("\(base)^\(e) = ?", value, "\(base)^\(e) means \(e) copies of \(base) multiplied: \(times(base, e)) = \(value).")
        case "sqrt":
            let n = dice.int(1, p("max", 15))
            return q("√\(n * n) = ?", n, "The square root asks which number times itself gives \(n * n). \(n) × \(n) = \(n * n).")

        // MARK: Algebra
        case "linearEq":
            let m = p("max", 10)
            var a = dice.int(1, 9); if dice.bool() { a = -a }
            let x = dice.int(-m, m), b = dice.int(-m, m), rhs = a * x + b
            let step1 = b == 0 ? "\(term(a, "x")) = \(rhs)" : "\(b > 0 ? "Subtract" : "Add") \(abs(b)) on both sides: \(term(a, "x")) = \(rhs - b)"
            return q("Solve for x:\n\(term(a, "x"))\(signed(b)) = \(rhs)", x,
                     "\(step1). \(a == 1 ? "" : "Divide both sides by \(a): ")x = \(x). Check: \(a) × \(x)\(signed(b)) = \(rhs).")
        case "proportion":
            let a = dice.int(1, 9), b = dice.int(2, 9), k = dice.int(2, 6)
            return q("\(a)/\(b) = x/\(b * k). What is x?", a * k, "The bottom went from \(b) to \(b * k), which is × \(k). Do the same to the top: \(a) × \(k) = \(a * k).")
        case "slope":
            let x1 = dice.int(-5, 5), dx = dice.int(1, 5), m = dice.int(-4, 4), y1 = dice.int(-5, 5)
            let y2 = y1 + m * dx
            return q("What is the slope of the line through (\(x1), \(y1)) and (\(x1 + dx), \(y2))?", m,
                     "Slope = rise ÷ run = (\(y2) − \(y1)) ÷ (\(x1 + dx) − \(x1)) = \(y2 - y1) ÷ \(dx) = \(m).")
        case "evalPoly":
            let a = dice.int(1, 4), b = dice.int(-5, 5), c = dice.int(-9, 9), k = dice.int(-3, 3)
            let value = a * k * k + b * k + c
            return q("f(x) = \(term(a, "x²"))\(signedTerm(b, "x"))\(signed(c)). What is f(\(k))?", value,
                     "Put \(k) in for x: \(a)(\(k))² + \(b)(\(k)) + \(c) = \(a * k * k) + \(b * k) + \(c) = \(value).")
        case "quadraticRoots":
            let r = dice.int(-9, 9)
            var s = dice.int(-9, 9); if s == r { s += 1 }
            return q("Solve x²\(signedTerm(-(r + s), "x"))\(signed(r * s)) = 0.\nGive the larger solution.", max(r, s),
                     "Find two numbers that multiply to \(r * s) and add to \(r + s): \(r) and \(s). So (x\(signed(-r)))(x\(signed(-s))) = 0 and x = \(r) or x = \(s). The larger is \(max(r, s)).")

        // MARK: Statistics and probability
        case "mean":
            let n = tier == 1 ? 3 : dice.int(3, 5)
            var values = (0..<(n - 1)).map { _ in dice.int(1, 20) }
            let target = dice.int(5, 15)
            values.append(target * n - values.reduce(0, +))
            if values.last! < 0 { return q("Mean of 2, 4, 6?", 4, "Add them: 2 + 4 + 6 = 12. Divide by how many (3): 12 ÷ 3 = 4.") }
            let shown = dice.shuffled(values).map(String.init)
            return q("What is the mean of \(shown.joined(separator: ", "))?", target,
                     "Add them: \(shown.joined(separator: " + ")) = \(target * n). Divide by how many (\(n)): \(target * n) ÷ \(n) = \(target).")
        case "median":
            let values = (0..<(tier == 1 ? 3 : 2 * dice.int(1, 3) + 1)).map { _ in dice.int(1, 50) }
            let sorted = values.sorted(), mid = sorted[values.count / 2]
            return q("What is the median of \(values.map(String.init).joined(separator: ", "))?", mid,
                     "Put them in order: \(sorted.map(String.init).joined(separator: ", ")). The middle one is \(mid).")
        case "probabilityDie":
            let k = dice.int(1, 5)
            return qs("A fair die is rolled. What is the probability of rolling a number greater than \(k)? (fraction)", "\(6 - k)/6",
                      "The numbers greater than \(k) are \(list(k + 1, 6)): \(6 - k) of the 6 equally likely sides. So \(6 - k)/6.")
        case "binomial":
            let n = dice.int(2, p("max", 10)), k = dice.int(0, n)
            let why = k == 0 || k == n ? "There is only 1 way to choose \(k == 0 ? "none" : "all of them")."
                : "\(n) choose \(k) = \(n)! ÷ (\(k)! × \(n - k)!) = \(choose(n, k)). (n! means n × (n − 1) × … × 1.)"
            return q("How many ways to choose \(k) items from \(n)? (\(n) choose \(k))", choose(n, k), why)

        // MARK: Number theory
        case "gcd":
            let m = p("max", 12)
            let g = dice.int(1, m), a = g * dice.int(1, m), b = g * dice.int(1, m)
            let ans = gcd(a, b)
            return q("gcd(\(a), \(b)) = ?", ans,
                     "\(ans) divides both: \(a) = \(ans) × \(a / ans) and \(b) = \(ans) × \(b / ans). \(a / ans) and \(b / ans) share no other factor, so \(ans) is the greatest.")
        case "lcm":
            let m = p("max", 15)
            let a = dice.int(2, m), b = dice.int(2, m)
            let ans = a / gcd(a, b) * b
            return q("lcm(\(a), \(b)) = ?", ans,
                     "Count up by \(max(a, b))s until you reach a number \(min(a, b)) divides: \(ans) = \(a) × \(ans / a) = \(b) × \(ans / b).")
        case "mod":
            let n = dice.int(2, p("max", 13)), a = dice.int(0, 200)
            return q("\(a) mod \(n) = ?", a % n, "\(a) = \(a / n) × \(n) + \(a % n). The remainder is \(a % n).")
        case "modInverse":
            let prime = dice.pick([5, 7, 11, 13]), a = dice.int(1, prime - 1)
            let inv = (1..<prime).first { (a * $0) % prime == 1 } ?? 1
            return q("Find the inverse of \(a) modulo \(prime) (a number from 1 to \(prime - 1)).", inv,
                     "The inverse times \(a) leaves remainder 1: \(a) × \(inv) = \(a * inv) = \(a * inv / prime) × \(prime) + 1.")
        case "eulerPhi":
            let n = dice.int(2, 40)
            let co = (1...n).filter { gcd($0, n) == 1 }
            return q("φ(\(n)) = ? (how many numbers from 1 to \(n) share no factor with \(n))", co.count,
                     co.count <= 16 ? "They are \(co.map(String.init).joined(separator: ", ")): \(co.count) numbers."
                                    : "Count the numbers from 1 to \(n) that share no factor with \(n): there are \(co.count).")
        case "groupOrder":
            let n = dice.int(4, 24), k = dice.int(1, n - 1), g = gcd(n, k)
            return q("In the group ℤ\(subscriptDigits(n)) under addition, what is the order of \(k)?", n / g,
                     "The order is how many times you add \(k) to get back to 0 (mod \(n)). That is \(n) ÷ gcd(\(n), \(k)) = \(n) ÷ \(g) = \(n / g).")

        // MARK: Calculus and series
        case "logBase":
            let base = dice.pick([2, 3, 5, 10]), e = dice.int(0, 4)
            let value = Int(pow(Double(base), Double(e)))
            return q("log base \(base) of \(value) = ?", e, e == 0 ? "Any base to the power 0 is 1, so the answer is 0."
                     : "\(base) to the power \(e) is \(value) (\(times(base, e))), so the logarithm is \(e).")
        case "derivative":
            let a = dice.int(1, 5), n = dice.int(2, 4), b = dice.int(-6, 6), k = dice.int(-2, 2)
            let kp = Int(pow(Double(k), Double(n - 1)))
            let value = a * n * kp + b
            return q("f(x) = \(term(a, "x^\(n)"))\(signedTerm(b, "x")). What is f′(\(k))?", value,
                     "Power rule: bring the power down and lower it by 1. f′(x) = \(a * n)x^\(n - 1)\(signed(b)). At x = \(k): \(a * n) × \(kp)\(signed(b)) = \(value).")
        case "integral":
            let a = dice.int(1, 6), k = dice.int(1, 5)
            return q("Evaluate the integral from 0 to \(k) of \(2 * a)x dx.", a * k * k,
                     "An antiderivative of \(2 * a)x is \(term(a, "x²")). Evaluate from 0 to \(k): \(a) × \(k * k) − 0 = \(a * k * k).")
        case "limit":
            let a = dice.int(-6, 6)
            return q("lim as x → \(a) of (x² − \(a * a)) / (x\(signed(-a))) = ?", 2 * a,
                     "Factor the top: x² − \(a * a) = (x\(signed(-a)))(x\(signed(a))). Cancel (x\(signed(-a))) to get x\(signed(a)), then put in x = \(a): \(2 * a).")
        case "geometricSeries":
            let a = dice.int(1, 20) * 2
            return q("\(a) + \(a / 2) + \(fmtHalf(a, 4)) + \(fmtHalf(a, 8)) + … (forever) = ?", 2 * a,
                     "Each term is half the one before. A geometric series with first term \(a) and ratio 1/2 adds up to \(a) ÷ (1 − 1/2) = \(2 * a).")

        // MARK: Linear algebra and complex numbers
        case "det2":
            let v = (0..<4).map { _ in dice.int(-6, 6) }
            let value = v[0] * v[3] - v[1] * v[2]
            return q("det [[\(v[0]), \(v[1])], [\(v[2]), \(v[3])]] = ?", value,
                     "ad − bc = (\(v[0]))(\(v[3])) − (\(v[1]))(\(v[2])) = \(v[0] * v[3]) − \(v[1] * v[2]) = \(value).")
        case "dot":
            let u = (0..<3).map { _ in dice.int(-5, 5) }, w = (0..<3).map { _ in dice.int(-5, 5) }
            let prods = zip(u, w).map { $0 * $1 }
            let sum = prods.reduce(0, +)
            return q("(\(u.map(String.init).joined(separator: ", "))) · (\(w.map(String.init).joined(separator: ", "))) = ?", sum,
                     "Multiply matching parts and add: " + zip(u, w).map { "(\($0))(\($1))" }.joined(separator: " + ")
                     + " = " + prods.map(String.init).joined(separator: " + ") + " = \(sum).")
        case "eigenTriangular":
            let a = dice.int(-6, 6), b = dice.int(-6, 6)
            var d = dice.int(-6, 6); if d == a { d += 1 }
            return q("The matrix [[\(a), \(b)], [0, \(d)]] has two eigenvalues. What is the larger one?", max(a, d),
                     "For a triangular matrix the eigenvalues are the numbers on the diagonal: \(a) and \(d). The larger is \(max(a, d)).")
        case "complexModulus":
            let t = dice.pick([(3, 4, 5), (5, 12, 13), (6, 8, 10), (8, 15, 17), (7, 24, 25)])
            return q("|\(t.0) + \(t.1)i| = ?", t.2,
                     "The size of a + bi is √(a² + b²) = √(\(t.0 * t.0) + \(t.1 * t.1)) = √\(t.2 * t.2) = \(t.2).")

        default:
            return nil
        }
    }

    // MARK: Helpers

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    static func choose(_ n: Int, _ k: Int) -> Int {
        guard k >= 0, k <= n else { return 0 }
        var r = 1
        for i in 0..<min(k, n - k) { r = r * (n - i) / (i + 1) }
        return r
    }

    /// "3x", "-x", "x"
    static func term(_ coef: Int, _ v: String) -> String {
        switch coef {
        case 1: return v
        case -1: return "-\(v)"
        default: return "\(coef)\(v)"
        }
    }

    /// " + 3x", " − x", "" for zero
    static func signedTerm(_ coef: Int, _ v: String) -> String {
        if coef == 0 { return "" }
        let body = abs(coef) == 1 ? v : "\(abs(coef))\(v)"
        return coef > 0 ? " + \(body)" : " − \(body)"
    }

    /// " + 3", " − 3", "" for zero
    static func signed(_ n: Int) -> String {
        n == 0 ? "" : (n > 0 ? " + \(n)" : " − \(-n)")
    }

    static func fmtTenths(_ tenths: Int) -> String { "\(tenths / 10).\(tenths % 10)" }

    /// a / divisor written as a whole number or fraction.
    static func fmtHalf(_ a: Int, _ divisor: Int) -> String {
        a % divisor == 0 ? "\(a / divisor)" : "\(a / gcd(a, divisor))/\(divisor / gcd(a, divisor))"
    }

    static func subscriptDigits(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
                                           "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        return String(String(n).map { map[$0] ?? $0 })
    }
}
