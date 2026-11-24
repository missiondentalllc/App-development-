import Foundation

/// Handwriting checker for short written answers (letters, words, numbers).
/// Same method as the web version (web/src/handwriting.js): the $P point-cloud recognizer
/// compares each box's strokes with model shapes from content/handwriting/templates.json,
/// ignoring stroke order and direction. The guide lines tell tall letters, tails and capitals
/// apart. Because the expected answer is known, each box is checked ("does this look like a d?")
/// rather than read freely; reversals (b, d, p, q and 6, 9) must be the best match.
///
/// Coordinates are in guide-line units: y = 2 top line, 1 middle line, 0 baseline, -1 tails.
public final class Handwriting {
    public typealias Stroke = [CGPoint]

    public struct BoxResult {
        public let ok: Bool
        public let read: String
    }

    public struct Result {
        public let correct: Bool
        public let read: String
        public let boxes: [BoxResult]
    }

    static let n = 32
    static let bandPenalty = 0.9
    static let tolerance = 1.18
    static let strict: [Set<String>] = [["b", "d", "p", "q"], ["6", "9"]]

    private struct Model { let ch: String; let cloud: [P]; let tall: Bool; let tail: Bool }
    private struct P { var x: Double; var y: Double; var id: Int }
    private var models: [Model] = []

    /// Loads templates.json (as bundled with the app).
    public init?(templatesJSON data: Data) {
        guard let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chars = doc["chars"] as? [String: [[[[Double]]]]] else { return nil }
        for (ch, variants) in chars {
            for strokes in variants {
                let s = strokes.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } }
                let b = Handwriting.band(s)
                models.append(Model(ch: ch, cloud: Handwriting.normalize(Handwriting.resample(Handwriting.points(s), Handwriting.n)),
                                    tall: b.tall, tail: b.tail))
            }
        }
    }

    /// Loads the templates bundled in the app (templates.json in the main bundle).
    public static func bundled() -> Handwriting? {
        guard let url = Bundle.main.url(forResource: "templates", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return Handwriting(templatesJSON: data)
    }

    // MARK: Checking

    public func checkAnswer(_ boxes: [[Stroke]], answer: String, matchCase: Bool = false) -> Result {
        let chars = answer.filter { !$0.isWhitespace }.map(String.init)
        let results = chars.enumerated().map { i, ch in checkBox(i < boxes.count ? boxes[i] : [], expected: ch, matchCase: matchCase) }
        return Result(correct: results.allSatisfy(\.ok), read: results.map { $0.read.isEmpty ? "_" : $0.read }.joined(), boxes: results)
    }

    public func checkBox(_ strokes: [Stroke], expected: String, matchCase: Bool = false) -> BoxResult {
        let digits = expected.rangeOfCharacter(from: .decimalDigits) != nil
        var ranked = rank(strokes, digits: digits)
        guard !ranked.isEmpty else { return BoxResult(ok: false, read: "") }
        var want = expected
        var shown: [String: String] = [:]
        if !matchCase {
            var merged: [String: Double] = [:]
            for r in ranked {
                let k = r.ch.lowercased()
                if merged[k] == nil || r.score < merged[k]! { merged[k] = r.score; shown[k] = r.ch }
            }
            ranked = merged.map { (ch: $0.key, score: $0.value) }.sorted { $0.score < $1.score }
            want = expected.lowercased()
        }
        let top = ranked[0]
        let mine = ranked.first { $0.ch == want }
        let isStrict = Handwriting.strict.contains { $0.contains(want) && $0.contains(top.ch) }
        let ok = top.ch == want || (mine != nil && !isStrict && mine!.score <= top.score * Handwriting.tolerance)
        let readKey = ok ? want : top.ch
        return BoxResult(ok: ok, read: shown[readKey] ?? readKey)
    }

    func rank(_ strokes: [Stroke], digits: Bool) -> [(ch: String, score: Double)] {
        let real = strokes.filter { !$0.isEmpty }
        let pts = Handwriting.points(real)
        guard pts.count >= 2 else { return [] }
        let cloud = Handwriting.normalize(Handwriting.resample(pts, Handwriting.n))
        let b = Handwriting.band(real)
        var best: [String: Double] = [:]
        for m in models where (m.ch.rangeOfCharacter(from: .decimalDigits) != nil) == digits {
            let score = Handwriting.greedyMatch(cloud, m.cloud)
                + (m.tall != b.tall ? Handwriting.bandPenalty : 0) + (m.tail != b.tail ? Handwriting.bandPenalty : 0)
            if best[m.ch] == nil || score < best[m.ch]! { best[m.ch] = score }
        }
        return best.map { (ch: $0.key, score: $0.value) }.sorted { $0.score < $1.score }
    }

    // MARK: $P

    private static func points(_ strokes: [Stroke]) -> [P] {
        strokes.enumerated().flatMap { id, s in s.map { P(x: Double($0.x), y: Double($0.y), id: id) } }
    }

    /// Tall / tail placement, ignoring dots (the dot on i and j sits above the middle line).
    private static func band(_ strokes: [Stroke]) -> (tall: Bool, tail: Bool) {
        var top = -Double.infinity, bottom = Double.infinity
        for s in strokes {
            var len = 0.0
            for i in 1..<max(s.count, 1) { len += hypot(Double(s[i].x - s[i - 1].x), Double(s[i].y - s[i - 1].y)) }
            if len < 0.35 { continue }
            for p in s { top = max(top, Double(p.y)); bottom = min(bottom, Double(p.y)) }
        }
        if top == -Double.infinity { return (false, false) }
        return (top > 1.45, bottom < -0.4)
    }

    private static func dist(_ a: P, _ b: P) -> Double { hypot(a.x - b.x, a.y - b.y) }

    private static func pathLength(_ pts: [P]) -> Double {
        var d = 0.0
        for i in 1..<max(pts.count, 1) where pts[i].id == pts[i - 1].id { d += dist(pts[i - 1], pts[i]) }
        return d
    }

    private static func resample(_ input: [P], _ n: Int) -> [P] {
        guard let first = input.first else { return [] }
        let interval = pathLength(input) / Double(n - 1)
        guard interval > 0 else { return Array(repeating: first, count: n) }
        var src = input
        var out = [first]
        var acc = 0.0
        var i = 1
        while i < src.count {
            if src[i].id == src[i - 1].id {
                let d = dist(src[i - 1], src[i])
                if acc + d >= interval {
                    let t = (interval - acc) / d
                    let q = P(x: src[i - 1].x + t * (src[i].x - src[i - 1].x),
                              y: src[i - 1].y + t * (src[i].y - src[i - 1].y), id: src[i].id)
                    out.append(q)
                    src.insert(q, at: i)
                    acc = 0
                } else {
                    acc += d
                }
            }
            i += 1
        }
        while out.count < n { out.append(src[src.count - 1]) }
        return Array(out.prefix(n))
    }

    private static func normalize(_ pts: [P]) -> [P] {
        let minX = pts.map(\.x).min() ?? 0, maxX = pts.map(\.x).max() ?? 0
        let minY = pts.map(\.y).min() ?? 0, maxY = pts.map(\.y).max() ?? 0
        let size = max(maxX - minX, maxY - minY, 1e-9)
        let scaled = pts.map { P(x: ($0.x - minX) / size, y: ($0.y - minY) / size, id: $0.id) }
        let cx = scaled.map(\.x).reduce(0, +) / Double(scaled.count)
        let cy = scaled.map(\.y).reduce(0, +) / Double(scaled.count)
        return scaled.map { P(x: $0.x - cx, y: $0.y - cy, id: $0.id) }
    }

    private static func cloudDistance(_ a: [P], _ b: [P], _ start: Int) -> Double {
        let n = a.count
        var matched = Array(repeating: false, count: n)
        var sum = 0.0
        var i = start
        repeat {
            var best = Double.infinity, index = -1
            for j in 0..<n where !matched[j] {
                let d = dist(a[i], b[j])
                if d < best { best = d; index = j }
            }
            matched[index] = true
            sum += (1 - Double((i - start + n) % n) / Double(n)) * best
            i = (i + 1) % n
        } while i != start
        return sum
    }

    private static func greedyMatch(_ a: [P], _ b: [P]) -> Double {
        let step = max(1, Int(Double(a.count).squareRoot()))
        var best = Double.infinity
        var i = 0
        while i < a.count {
            best = min(best, cloudDistance(a, b, i), cloudDistance(b, a, i))
            i += step
        }
        return best
    }
}
