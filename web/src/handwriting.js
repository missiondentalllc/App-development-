// Handwriting checker for short written answers (letters, words, numbers).
//
// Each answer box holds one character. The child's strokes are compared with model
// shapes (content/handwriting/templates.json) using the $P point-cloud recognizer
// (Vatavu, Anthony & Wobbrock, 2012), which ignores stroke order and direction, so a
// letter drawn "the wrong way" still counts if it looks right. The guide lines tell
// tall letters, tails and capitals apart (c and C have the same shape, different size).
//
// Because the app knows the expected answer, it checks "does this look like a d?"
// rather than reading freely. A box passes when the expected character is the best
// match or nearly as good as the best, except that reversals (b, d, p, q and 6, 9)
// must be the best match: catching reversals is the point of first-grade writing.
"use strict";

const Handwriting = (() => {
  const N = 32;              // points per shape after resampling
  const BAND_PENALTY = 0.9;  // added when tall/tail placement doesn't match the model
  const TOLERANCE = 1.18;    // expected char may score up to 18% worse than the best
  const STRICT = [new Set(["b", "d", "p", "q"]), new Set(["6", "9"])];
  let models = null;         // [{ ch, cloud, tall, tail }]

  // ---- $P core ----
  function pathLength(pts) {
    let d = 0;
    for (let i = 1; i < pts.length; i++) if (pts[i].id === pts[i - 1].id) d += dist(pts[i - 1], pts[i]);
    return d;
  }
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

  function resample(pts, n) {
    const I = pathLength(pts) / (n - 1);
    if (!(I > 0)) return Array.from({ length: n }, () => ({ ...pts[0] }));
    const src = pts.map(p => ({ ...p }));
    const out = [{ ...src[0] }];
    let D = 0;
    for (let i = 1; i < src.length; i++) {
      if (src[i].id !== src[i - 1].id) continue;
      const d = dist(src[i - 1], src[i]);
      if (D + d >= I) {
        const t = (I - D) / d;
        const q = { x: src[i - 1].x + t * (src[i].x - src[i - 1].x), y: src[i - 1].y + t * (src[i].y - src[i - 1].y), id: src[i].id };
        out.push(q);
        src.splice(i, 0, q);
        D = 0;
      } else D += d;
    }
    while (out.length < n) out.push({ ...src[src.length - 1] });
    return out.slice(0, n);
  }

  function normalize(pts) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const p of pts) { minX = Math.min(minX, p.x); maxX = Math.max(maxX, p.x); minY = Math.min(minY, p.y); maxY = Math.max(maxY, p.y); }
    const size = Math.max(maxX - minX, maxY - minY) || 1;
    const scaled = pts.map(p => ({ x: (p.x - minX) / size, y: (p.y - minY) / size, id: p.id }));
    const cx = scaled.reduce((s, p) => s + p.x, 0) / scaled.length, cy = scaled.reduce((s, p) => s + p.y, 0) / scaled.length;
    return scaled.map(p => ({ x: p.x - cx, y: p.y - cy, id: p.id }));
  }

  function cloudDistance(a, b, start) {
    const n = a.length, matched = new Array(n).fill(false);
    let sum = 0, i = start;
    do {
      let min = Infinity, index = -1;
      for (let j = 0; j < n; j++) if (!matched[j]) { const d = dist(a[i], b[j]); if (d < min) { min = d; index = j; } }
      matched[index] = true;
      sum += (1 - ((i - start + n) % n) / n) * min;
      i = (i + 1) % n;
    } while (i !== start);
    return sum;
  }

  function greedyMatch(a, b) {
    const step = Math.floor(Math.pow(a.length, 0.5));
    let min = Infinity;
    for (let i = 0; i < a.length; i += step) min = Math.min(min, cloudDistance(a, b, i), cloudDistance(b, a, i));
    return min;
  }

  // ---- shapes in guide-line units: y = 2 top, 1 middle, 0 baseline, -1 tails ----
  function toPoints(strokes) {
    const pts = [];
    strokes.forEach((s, id) => s.forEach(p => pts.push({ x: p[0], y: p[1], id })));
    return pts;
  }

  // Tall / tail placement, ignoring dots (the dot on i and j sits above the middle line).
  function band(strokes) {
    let top = -Infinity, bottom = Infinity;
    for (const s of strokes) {
      const len = s.reduce((d, p, i) => d + (i ? Math.hypot(p[0] - s[i - 1][0], p[1] - s[i - 1][1]) : 0), 0);
      if (len < 0.35) continue;
      for (const p of s) { top = Math.max(top, p[1]); bottom = Math.min(bottom, p[1]); }
    }
    if (top === -Infinity) return { tall: false, tail: false };
    return { tall: top > 1.45, tail: bottom < -0.4 };
  }

  function load(templateDoc) {
    models = [];
    for (const [ch, variants] of Object.entries(templateDoc.chars)) {
      for (const strokes of variants) {
        const b = band(strokes);
        models.push({ ch, cloud: normalize(resample(toPoints(strokes), N)), tall: b.tall, tail: b.tail });
      }
    }
  }

  /** Rank characters for one box. strokes: [[[x, y], ...], ...] in guide-line units. */
  function rank(strokes, { digits = false } = {}) {
    const real = strokes.filter(s => s.length);
    if (!real.length) return [];
    const pts = toPoints(real);
    if (pts.length < 2) return [];
    const cloud = normalize(resample(pts, N));
    const b = band(real);
    const best = {};
    for (const m of models) {
      if (digits !== /[0-9]/.test(m.ch)) continue;
      const score = greedyMatch(cloud, m.cloud) + (m.tall !== b.tall ? BAND_PENALTY : 0) + (m.tail !== b.tail ? BAND_PENALTY : 0);
      if (best[m.ch] == null || score < best[m.ch]) best[m.ch] = score;
    }
    return Object.entries(best).map(([ch, score]) => ({ ch, score })).sort((x, y) => x.score - y.score);
  }

  /** Does this box look like the expected character? */
  function checkBox(strokes, expected, { matchCase = false } = {}) {
    const digits = /[0-9]/.test(expected);
    let ranked = rank(strokes, { digits });
    if (!ranked.length) return { ok: false, read: "", empty: true };
    if (!matchCase) {
      // Same letter in either case counts as one.
      const merged = {};
      for (const r of ranked) { const k = r.ch.toLowerCase(); if (merged[k] == null || r.score < merged[k].score) merged[k] = { ch: k, score: r.score, shown: r.ch }; }
      ranked = Object.values(merged).sort((x, y) => x.score - y.score);
      expected = expected.toLowerCase();
    }
    const top = ranked[0], mine = ranked.find(r => r.ch === expected);
    const strict = STRICT.some(g => g.has(expected) && g.has(top.ch));
    const ok = top.ch === expected || (!!mine && !strict && mine.score <= top.score * TOLERANCE);
    return { ok, read: ok ? (mine.shown || mine.ch) : (top.shown || top.ch), ranked: ranked.slice(0, 3) };
  }

  /**
   * Check a written answer. boxes: one stroke list per answer character, in guide-line units.
   * Returns { correct, read, boxes }.
   */
  function checkAnswer(boxes, answer, opts = {}) {
    const chars = [...answer.replace(/\s+/g, "")];
    const results = chars.map((ch, i) => checkBox(boxes[i] || [], ch, opts));
    return { correct: results.every(r => r.ok), read: results.map(r => r.read || "_").join(""), boxes: results };
  }

  return { load, rank, checkBox, checkAnswer, get ready() { return !!models; } };
})();

if (typeof module !== "undefined") module.exports = { Handwriting };
