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
        func q(_ prompt: String, _ answer: Int) -> Question {
            Question(skillId: skillId, prompt: prompt, answer: String(answer))
        }
        func qs(_ prompt: String, _ answer: String) -> Question {
            Question(skillId: skillId, prompt: prompt, answer: answer)
        }
        func mc(_ prompt: String, _ choices: [String], _ answer: String) -> Question {
            Question(skillId: skillId, prompt: prompt, choices: choices, answer: answer)
        }

        switch key {

        // MARK: Counting and number sense
        case "count":
            let n = dice.int(1, p("max", 20))
            let dots = (0..<n).map { $0 > 0 && $0 % 5 == 0 ? " ●" : "●" }.joined()
            return q("How many dots?\n\(dots)", n)
        case "countBy":
            let step = p("step", 1)
            let start = step * dice.int(0, max(0, p("max", 100) / step - 3))
            return q("What comes next?\n\(start), \(start + step), \(start + 2 * step), __", start + 3 * step)
        case "numberAfter":
            let n = dice.int(1, p("max", 120))
            return dice.bool() ? q("What number comes just after \(n)?", n + 1)
                               : q("What number comes just before \(n)?", n - 1)
        case "compare":
            let a = dice.int(0, p("max", 100))
            var b = dice.int(0, p("max", 100))
            if dice.int(0, 5) == 0 { b = a }
            let symbol = a > b ? ">" : (a < b ? "<" : "=")
            return mc("Which sign goes in the blank?\n\(a) __ \(b)", [">", "<", "="], symbol)
        case "placeValue":
            let digits = max(2, min(4, p("digits", 2)))
            let n = dice.int(Int(pow(10.0, Double(digits - 1))), Int(pow(10.0, Double(digits))) - 1)
            let places = ["ones", "tens", "hundreds", "thousands"]
            let i = dice.int(0, digits - 1)
            let digit = (n / Int(pow(10.0, Double(i)))) % 10
            return q("What digit is in the \(places[i]) place of \(n)?", digit)
        case "tenMore":
            let n = dice.int(10, max(10, p("max", 100) - 10))
            return dice.bool() ? q("What is 10 more than \(n)?", n + 10) : q("What is 10 less than \(n)?", n - 10)
        case "evenOdd":
            let n = dice.int(0, p("max", 50))
            return mc("Is \(n) even or odd?", ["Even", "Odd"], n % 2 == 0 ? "Even" : "Odd")
        case "roundTen":
            let n = dice.int(0, p("max", 100))
            return q("Round \(n) to the nearest ten.", Int((Double(n) / 10).rounded(.toNearestOrAwayFromZero)) * 10)

        // MARK: Addition and subtraction
        case "add":
            let m = p("max", 10)
            let a = dice.int(0, m), b = dice.int(0, m)
            return q("\(a) + \(b) = ?", a + b)
        case "add3":
            let m = p("max", 9)
            let a = dice.int(0, m), b = dice.int(0, m), c = dice.int(0, m)
            return q("\(a) + \(b) + \(c) = ?", a + b + c)
        case "sub":
            let a = dice.int(0, p("max", 10)), b = dice.int(0, a)
            return q("\(a) − \(b) = ?", a - b)
        case "missingAddend":
            let c = dice.int(0, p("max", 10)), a = dice.int(0, c)
            return q("\(a) + ? = \(c)", c - a)
        case "makeTen":
            let a = dice.int(0, 10)
            return q("\(a) + ? = 10", 10 - a)
        case "doubles":
            let n = dice.int(0, p("max", 10))
            return q("\(n) + \(n) = ?", 2 * n)
        case "factFamily":
            let m = p("max", 10)
            let a = dice.int(1, m), b = dice.int(1, m)
            return q("If \(a) + \(b) = \(a + b), what is \(a + b) − \(b)?", a)
        case "wordAdd":
            let m = p("max", 10)
            let a = dice.int(1, m), b = dice.int(1, m)
            let thing = dice.pick(["apples", "stickers", "blocks", "shells", "crayons"])
            if dice.bool() {
                return q("Sam has \(a) \(thing). Sam gets \(b) more. How many \(thing) now?", a + b)
            }
            let big = a + b
            return q("Sam has \(big) \(thing). Sam gives away \(b). How many \(thing) are left?", a)
        case "money":
            // Starter: dimes and pennies only. Core adds nickels. Challenge adds quarters.
            let quarters = tier >= 3 ? dice.int(0, 3) : 0, dimes = dice.int(0, 4)
            let nickels = tier >= 2 ? dice.int(0, 3) : 0, pennies = dice.int(0, 4)
            let coins: [(Int, String, String)] = [(quarters, "quarter", "quarters"), (dimes, "dime", "dimes"),
                                                  (nickels, "nickel", "nickels"), (pennies, "penny", "pennies")]
            let parts = coins.filter { $0.0 > 0 }.map { coin -> String in
                coin.0 == 1 ? "1 " + coin.1 : String(coin.0) + " " + coin.2
            }
            let total = quarters * 25 + dimes * 10 + nickels * 5 + pennies
            if parts.isEmpty { return q("How many cents is 1 dime?", 10) }
            return q("How many cents?\n" + parts.joined(separator: ", "), total)
        case "time":
            let h = dice.int(1, 12)
            if tier == 1 || dice.bool() {
                return qs("The short hand points to \(h). The long hand points to 12. What time is it?", "\(h):00")
            }
            let nextHour = h == 12 ? 1 : h + 1
            return qs("The short hand is between \(h) and \(nextHour). The long hand points to 6. What time is it?", "\(h):30")

        // MARK: Multiplication, division, fractions, decimals
        case "mul":
            let a = dice.int(p("min", 0), p("max", 10)), b = dice.int(p("min", 0), p("max", 10))
            return q("\(a) × \(b) = ?", a * b)
        case "div":
            let b = dice.int(1, p("max", 10)), quotient = dice.int(0, p("max", 10))
            return q("\(b * quotient) ÷ \(b) = ?", quotient)
        case "orderOps":
            let a = dice.int(1, 9), b = dice.int(1, 9), c = dice.int(1, 9)
            return dice.bool() ? q("\(a) + \(b) × \(c) = ?", a + b * c) : q("(\(a) + \(b)) × \(c) = ?", (a + b) * c)
        case "fractionOf":
            let d = dice.int(2, p("maxDen", 10)), n = d * dice.int(1, 10)
            return q("What is 1/\(d) of \(n)?", n / d)
        case "fractionAdd":
            let d = dice.int(2, p("maxDen", 12)), a = dice.int(1, d), b = dice.int(1, d)
            return qs("\(a)/\(d) + \(b)/\(d) = ?", "\(a + b)/\(d)")
        case "fractionCompare":
            let d1 = dice.int(2, 12), d2 = dice.int(2, 12)
            let n1 = dice.int(1, d1), n2 = dice.int(1, d2)
            if n1 * d2 == n2 * d1 { return mc("Which is greater?", ["\(n1)/\(d1)", "\(n1 + 1)/\(d1)"], "\(n1 + 1)/\(d1)") }
            let bigger = n1 * d2 > n2 * d1 ? "\(n1)/\(d1)" : "\(n2)/\(d2)"
            return mc("Which is greater?", ["\(n1)/\(d1)", "\(n2)/\(d2)"], bigger)
        case "decimalAdd":
            let a = dice.int(1, 99), b = dice.int(1, 99)
            return qs("\(fmtTenths(a)) + \(fmtTenths(b)) = ?", fmtTenths(a + b))
        case "percent":
            let pct = dice.pick([10, 20, 25, 50, 75]), n = 20 * dice.int(1, 10)
            return q("What is \(pct)% of \(n)?", pct * n / 100)

        // MARK: Integers, powers, roots
        case "integerAdd":
            let m = p("max", 20)
            let a = dice.int(-m, m), b = dice.int(-m, m)
            return q("(\(a)) + (\(b)) = ?", a + b)
        case "integerMul":
            let m = p("max", 12)
            let a = dice.int(-m, m), b = dice.int(-m, m)
            return q("(\(a)) × (\(b)) = ?", a * b)
        case "exponent":
            let base = dice.int(2, p("maxBase", 6)), e = dice.int(2, base <= 3 ? 5 : 3)
            return q("\(base)^\(e) = ?", Int(pow(Double(base), Double(e))))
        case "sqrt":
            let n = dice.int(1, p("max", 15))
            return q("√\(n * n) = ?", n)

        // MARK: Algebra
        case "linearEq":
            let m = p("max", 10)
            var a = dice.int(1, 9); if dice.bool() { a = -a }
            let x = dice.int(-m, m), b = dice.int(-m, m)
            return q("Solve for x:\n\(term(a, "x"))\(signed(b)) = \(a * x + b)", x)
        case "proportion":
            let a = dice.int(1, 9), b = dice.int(2, 9), k = dice.int(2, 6)
            return q("\(a)/\(b) = x/\(b * k). What is x?", a * k)
        case "slope":
            let x1 = dice.int(-5, 5), dx = dice.int(1, 5), m = dice.int(-4, 4), y1 = dice.int(-5, 5)
            return q("What is the slope of the line through (\(x1), \(y1)) and (\(x1 + dx), \(y1 + m * dx))?", m)
        case "evalPoly":
            let a = dice.int(1, 4), b = dice.int(-5, 5), c = dice.int(-9, 9), k = dice.int(-3, 3)
            return q("f(x) = \(term(a, "x²"))\(signedTerm(b, "x"))\(signed(c)). What is f(\(k))?", a * k * k + b * k + c)
        case "quadraticRoots":
            let r = dice.int(-9, 9)
            var s = dice.int(-9, 9); if s == r { s += 1 }
            return q("Solve x²\(signedTerm(-(r + s), "x"))\(signed(r * s)) = 0.\nGive the larger solution.", max(r, s))

        // MARK: Statistics and probability
        case "mean":
            let n = tier == 1 ? 3 : dice.int(3, 5)
            var values = (0..<(n - 1)).map { _ in dice.int(1, 20) }
            let target = dice.int(5, 15)
            values.append(target * n - values.reduce(0, +))
            if values.last! < 0 { return q("Mean of 2, 4, 6?", 4) }
            return q("What is the mean of \(dice.shuffled(values).map(String.init).joined(separator: ", "))?", target)
        case "median":
            let values = (0..<(tier == 1 ? 3 : 2 * dice.int(1, 3) + 1)).map { _ in dice.int(1, 50) }
            return q("What is the median of \(values.map(String.init).joined(separator: ", "))?", values.sorted()[values.count / 2])
        case "probabilityDie":
            let k = dice.int(1, 5)
            return qs("A fair die is rolled. What is the probability of rolling a number greater than \(k)? (fraction)", "\(6 - k)/6")
        case "binomial":
            let n = dice.int(2, p("max", 10)), k = dice.int(0, n)
            return q("How many ways to choose \(k) items from \(n)? (\(n) choose \(k))", choose(n, k))

        // MARK: Number theory
        case "gcd":
            let g = dice.int(1, 12), a = g * dice.int(1, 12), b = g * dice.int(1, 12)
            return q("gcd(\(a), \(b)) = ?", gcd(a, b))
        case "lcm":
            let a = dice.int(2, 15), b = dice.int(2, 15)
            return q("lcm(\(a), \(b)) = ?", a / gcd(a, b) * b)
        case "mod":
            let n = dice.int(2, p("max", 13)), a = dice.int(0, 200)
            return q("\(a) mod \(n) = ?", a % n)
        case "modInverse":
            let prime = dice.pick([5, 7, 11, 13]), a = dice.int(1, prime - 1)
            let inv = (1..<prime).first { (a * $0) % prime == 1 } ?? 1
            return q("Find the inverse of \(a) modulo \(prime) (a number from 1 to \(prime - 1)).", inv)
        case "eulerPhi":
            let n = dice.int(2, 40)
            return q("φ(\(n)) = ? (how many numbers from 1 to \(n) share no factor with \(n))", (1...n).filter { gcd($0, n) == 1 }.count)
        case "groupOrder":
            let n = dice.int(4, 24), k = dice.int(1, n - 1)
            return q("In the group ℤ\(subscriptDigits(n)) under addition, what is the order of \(k)?", n / gcd(n, k))

        // MARK: Calculus and series
        case "logBase":
            let base = dice.pick([2, 3, 5, 10]), e = dice.int(0, 4)
            return q("log base \(base) of \(Int(pow(Double(base), Double(e)))) = ?", e)
        case "derivative":
            let a = dice.int(1, 5), n = dice.int(2, 4), b = dice.int(-6, 6), k = dice.int(-2, 2)
            let value = a * n * Int(pow(Double(k), Double(n - 1))) + b
            return q("f(x) = \(term(a, "x^\(n)"))\(signedTerm(b, "x")). What is f′(\(k))?", value)
        case "integral":
            let a = dice.int(1, 6), k = dice.int(1, 5)
            return q("Evaluate the integral from 0 to \(k) of \(2 * a)x dx.", a * k * k)
        case "limit":
            let a = dice.int(-6, 6)
            return q("lim as x → \(a) of (x² − \(a * a)) / (x\(signed(-a))) = ?", 2 * a)
        case "geometricSeries":
            let a = dice.int(1, 20) * 2
            return q("\(a) + \(a / 2) + \(fmtHalf(a, 4)) + \(fmtHalf(a, 8)) + … (forever) = ?", 2 * a)

        // MARK: Linear algebra and complex numbers
        case "det2":
            let v = (0..<4).map { _ in dice.int(-6, 6) }
            return q("det [[\(v[0]), \(v[1])], [\(v[2]), \(v[3])]] = ?", v[0] * v[3] - v[1] * v[2])
        case "dot":
            let u = (0..<3).map { _ in dice.int(-5, 5) }, w = (0..<3).map { _ in dice.int(-5, 5) }
            return q("(\(u.map(String.init).joined(separator: ", "))) · (\(w.map(String.init).joined(separator: ", "))) = ?",
                     zip(u, w).map { $0 * $1 }.reduce(0, +))
        case "eigenTriangular":
            let a = dice.int(-6, 6), b = dice.int(-6, 6)
            var d = dice.int(-6, 6); if d == a { d += 1 }
            return q("The matrix [[\(a), \(b)], [0, \(d)]] has two eigenvalues. What is the larger one?", max(a, d))
        case "complexModulus":
            let t = dice.pick([(3, 4, 5), (5, 12, 13), (6, 8, 10), (8, 15, 17), (7, 24, 25)])
            return q("|\(t.0) + \(t.1)i| = ?", t.2)

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
