#if canImport(SwiftUI)
import SwiftUI
import AVFoundation

/// What has been written on a pad. Stroke points are in view points.
public final class PadModel: ObservableObject {
    @Published public var strokes: [[CGPoint]] = []
    /// Copy of the last checked writing, shown on the feedback screen.
    @Published public var snapshot: [[CGPoint]] = []
    public var size: CGSize = .zero
    /// True while a finger or pencil is down.
    var drawing = false

    public init() {}

    public var hasInk: Bool { strokes.contains { $0.count > 1 } }
    public func undo() { if !strokes.isEmpty { strokes.removeLast() } }
    public func clear() { strokes = [] }
    public func keepSnapshot() { snapshot = strokes }

    /// Guide geometry for one row of height `rowH`: one unit = middle line to baseline.
    static func unit(rowHeight: CGFloat) -> CGFloat { rowHeight / 4.4 }
    static func baseline(row: Int, rowHeight: CGFloat) -> CGFloat {
        CGFloat(row) * rowHeight + rowHeight * 0.12 + 2 * unit(rowHeight: rowHeight)
    }

    /// Strokes per box, in guide-line units (y = 2 top, 1 middle, 0 baseline, -1 tails).
    public func boxes(cells: Int) -> [[Handwriting.Stroke]] {
        guard cells > 0, size.width > 0 else { return [] }
        let cw = size.width / CGFloat(cells)
        let u = PadModel.unit(rowHeight: size.height), base = PadModel.baseline(row: 0, rowHeight: size.height)
        var out = Array(repeating: [Handwriting.Stroke](), count: cells)
        for s in strokes where !s.isEmpty {
            let cx = s.map(\.x).reduce(0, +) / CGFloat(s.count)
            let i = min(cells - 1, max(0, Int(cx / cw)))
            out[i].append(s.map { CGPoint(x: ($0.x - CGFloat(i) * cw) / u, y: (base - $0.y) / u) })
        }
        return out
    }
}

/// Lined like first-grade handwriting paper: solid top line, dashed middle line, solid
/// baseline and room below for tails. `cells` > 0 splits one row into answer boxes;
/// `cells` == 0 gives free writing paper with `rows` lines.
public struct WritingPad: View {
    @ObservedObject var model: PadModel
    let cells: Int
    let rows: Int
    var interactive = true
    var showSnapshot = false

    public init(model: PadModel, cells: Int, rows: Int = 1, interactive: Bool = true, showSnapshot: Bool = false) {
        self.model = model
        self.cells = cells
        self.rows = rows
        self.interactive = interactive
        self.showSnapshot = showSnapshot
    }

    public var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let rowH = size.height / CGFloat(rows), u = PadModel.unit(rowHeight: rowH)
                for r in 0..<rows {
                    let b = PadModel.baseline(row: r, rowHeight: rowH)
                    func hline(_ y: CGFloat, _ dash: [CGFloat], _ color: Color, _ width: CGFloat) {
                        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
                    }
                    hline(b - 2 * u, [], .secondary.opacity(0.4), 1.5)
                    hline(b - u, [6, 6], .secondary.opacity(0.4), 1.5)
                    hline(b, [], .accentColor, 2)
                    hline(b + u, [2, 6], .secondary.opacity(0.3), 1)
                }
                if cells > 1 {
                    for i in 1..<cells {
                        let x = size.width / CGFloat(cells) * CGFloat(i)
                        var p = Path(); p.move(to: CGPoint(x: x, y: 6)); p.addLine(to: CGPoint(x: x, y: size.height - 6))
                        ctx.stroke(p, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
                    }
                }
                for s in (showSnapshot ? model.snapshot : model.strokes) {
                    var p = Path()
                    if let first = s.first { p.move(to: first) }
                    for pt in s.dropFirst() { p.addLine(to: pt) }
                    if s.count == 1, let f = s.first { p.addLine(to: CGPoint(x: f.x + 0.1, y: f.y + 0.1)) }
                    ctx.stroke(p, with: .color(.primary), style: StrokeStyle(lineWidth: max(3, u * 0.16), lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(interactive ? drawing : nil)
            .onAppear { if interactive { model.size = geo.size } }
            .onChange(of: geo.size) { _, new in if interactive { model.size = new } }
        }
        .frame(height: cells > 0 ? 170 : 420)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3)))
        .accessibilityLabel(cells > 0 ? "Writing boxes" : "Writing paper")
    }

    private var drawing: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !model.drawing {
                    model.drawing = true
                    model.strokes.append([v.location])
                } else {
                    model.strokes[model.strokes.count - 1].append(v.location)
                }
            }
            .onEnded { _ in model.drawing = false }
    }
}

/// Reads a word aloud (spelling dictation).
public enum Speaker {
    private static let synth = AVSpeechSynthesizer()
    public static func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}
#endif
