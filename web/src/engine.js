// TutorCore for the web: a line-by-line port of packages/TutorCore (Swift).
// Same rules as the iPhone apps: speed-weighted comprehension, gap-first repair,
// spaced review, placement test, question generators.
"use strict";

const DAY_MS = 86400000;

// ---------- Comprehension ----------
const Comprehension = {
  questionCapSeconds: 60,
  defaultSightPace: 5,
  smoothing: 0.3,
  passThreshold: 0.70,
  masteryThreshold: 0.85,
  sightThreshold: 0.95,
  minAttemptsForMastery: 5,

  speedScore(seconds, sightPace) {
    const pace = Math.max(1, sightPace);
    if (seconds <= pace) return 1;
    if (seconds >= this.questionCapSeconds) return 0;
    return (this.questionCapSeconds - seconds) / (this.questionCapSeconds - pace);
  },

  answerScore(correct, seconds, sightPace) {
    if (!correct) return 0;
    return 0.5 + 0.5 * this.speedScore(seconds, sightPace);
  },

  record(state, correct, seconds, sightPace, now = Date.now()) {
    const s = { ...newSkillState(), ...state };
    const pace = sightPace ?? this.defaultSightPace;
    const clamped = Math.min(Math.max(seconds, 0), this.questionCapSeconds);
    const score = this.answerScore(correct, clamped, pace);
    if (s.attempts === 0 || s.provisional) s.comprehension = score;
    else s.comprehension = this.smoothing * score + (1 - this.smoothing) * s.comprehension;
    s.provisional = false;
    s.attempts += 1;
    if (correct) s.correct += 1;
    s.averageSeconds = ((s.averageSeconds ?? clamped) * (s.attempts - 1) + clamped) / s.attempts;
    s.lastPracticed = now;
    Tiers.update(s, correct);
    return SpacedReview.schedule(s, correct, clamped <= pace * 1.5, now);
  },

  level(s) {
    s = s || newSkillState();
    if (s.attempts === 0 && !s.provisional) return "new";
    // Mastered and sight-level need the Challenge tier: the skill at full difficulty.
    const top = Tiers.current(s) === 3;
    if (top && s.comprehension >= this.sightThreshold && s.attempts >= this.minAttemptsForMastery) return "sight";
    if (top && s.comprehension >= this.masteryThreshold && (s.attempts >= this.minAttemptsForMastery || s.provisional)) return "mastered";
    if (s.comprehension >= this.passThreshold) return "passing";
    return "learning";
  },

  /** 100% mastered: sight-level (right, fast, at full difficulty). */
  isFullyMastered(s) { return this.level(s) === "sight"; },

  isPassed(s) { return (s?.comprehension ?? 0) >= this.passThreshold; },

  levelLabel: { new: "Not started", learning: "Learning", passing: "Passing", mastered: "Mastered", sight: "Sight-level" },
};

function newSkillState() {
  return { attempts: 0, correct: 0, comprehension: 0, provisional: false,
           lastPracticed: null, reviewBox: 0, nextReview: null, averageSeconds: null,
           tier: 1, rightStreak: 0, missStreak: 0 };
}

// ---------- Difficulty tiers ----------
// Every skill has three tiers: Starter, Core, Challenge (the skill at full difficulty).
// Two right in a row moves up a tier; two misses in a row moves down one.
const Tiers = {
  names: { 1: "Starter", 2: "Core", 3: "Challenge" },
  current(s) {
    if (!s) return 1;
    if (s.tier >= 1 && s.tier <= 3) return s.tier;
    // Progress saved before tiers existed: place by score.
    if (s.provisional) return 3;
    if (s.comprehension >= Comprehension.masteryThreshold) return 3;
    if (s.comprehension >= Comprehension.passThreshold) return 2;
    return 1;
  },
  update(s, correct) {
    let t = this.current(s);
    if (correct) {
      s.rightStreak = (s.rightStreak || 0) + 1; s.missStreak = 0;
      if (s.rightStreak >= 2 && t < 3) { t += 1; s.rightStreak = 0; }
    } else {
      s.missStreak = (s.missStreak || 0) + 1; s.rightStreak = 0;
      if (s.missStreak >= 2 && t > 1) { t -= 1; s.missStreak = 0; }
    }
    s.tier = t;
  },
};

// ---------- Parts of a level and teaching approaches ----------
const PartNames = { 1: "Foundations", 2: "Building", 3: "Mastery" };
const Approaches = [
  { key: "show", name: "Show", blurb: "You show it while they watch." },
  { key: "together", name: "Do together", blurb: "Do one together, taking turns." },
  { key: "alone", name: "Try alone", blurb: "They try one alone; you give one hint only if stuck." },
];

// ---------- Spaced review ----------
const SpacedReview = {
  intervalsInDays: [1, 2, 4, 8, 16, 32, 64],
  schedule(state, correct, fast, now) {
    const s = { ...state };
    if (!correct) s.reviewBox = 0;
    else if (fast) s.reviewBox = Math.min(s.reviewBox + 1, this.intervalsInDays.length - 1);
    const d = new Date(now);
    d.setDate(d.getDate() + this.intervalsInDays[s.reviewBox]);
    s.nextReview = d.getTime();
    return s;
  },
  isDue(s, now = Date.now()) {
    if (!s || s.attempts <= 0 || s.nextReview == null) return false;
    return s.nextReview <= now;
  },
};

// ---------- Curriculum helpers ----------
function hasPractice(skill) {
  return !!skill.practice?.generator || (skill.practice?.items || []).length > 0;
}

// ---------- Short forms (glossary) ----------
// Each curriculum lists its abbreviations with plain-English meanings. Any text
// shown to the learner is scanned so the meaning of every short form appears with it.
function shortFormsIn(curriculum, texts) {
  const list = curriculum.glossary || [];
  if (!curriculum._glossaryRe) {
    const escape = t => t.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&");
    curriculum._glossaryRe = list.map(g => new RegExp(`(?<![A-Za-z-])${escape(g.term)}s?(?![A-Za-z-])`));
  }
  const text = texts.filter(Boolean).join("\n");
  return list.filter((g, i) => curriculum._glossaryRe[i].test(text));
}

// ---------- Skill graph ----------
class SkillGraph {
  constructor(curriculum) {
    this.curriculum = curriculum;
    this.index = {};
    const deps = {};
    for (const s of curriculum.skills) {
      this.index[s.id] = s;
      for (const p of s.prerequisites || []) (deps[p] = deps[p] || []).push(s.id);
    }
    this.dependents = deps;
    this.impact = {};
    for (const s of curriculum.skills) {
      const seen = new Set();
      const stack = [...(deps[s.id] || [])];
      while (stack.length) {
        const next = stack.pop();
        if (!seen.has(next)) { seen.add(next); stack.push(...(deps[next] || [])); }
      }
      this.impact[s.id] = seen.size;
    }
    const stageOrder = Object.fromEntries(curriculum.stages.map(st => [st.id, st.order]));
    const position = Object.fromEntries(curriculum.skills.map((s, i) => [s.id, i]));
    this.ordered = [...curriculum.skills].sort((x, y) => {
      const a = stageOrder[x.stage] ?? 0, b = stageOrder[y.stage] ?? 0;
      if (a !== b) return a - b;
      if (x.day != null && y.day != null && x.day !== y.day) return x.day - y.day;
      return position[x.id] - position[y.id];
    });
    this.stagesSorted = [...curriculum.stages].sort((a, b) => a.order - b.order);
  }
  skill(id) { return this.index[id]; }
  stage(id) { return this.curriculum.stages.find(s => s.id === id); }
  skillsIn(stageId) { return this.curriculum.skills.filter(s => s.stage === stageId); }
  /** The level's three parts. Uses each skill's "part"; otherwise splits the level into thirds. */
  partsOf(stageId) {
    const skills = this.ordered.filter(s => s.stage === stageId);
    const partOf = (s, i) => s.part || Math.min(3, Math.floor((i * 3) / Math.max(skills.length, 1)) + 1);
    return [1, 2, 3].map(n => ({ n, name: PartNames[n], skills: skills.filter((s, i) => partOf(s, i) === n) }));
  }
  partOfSkill(skill) {
    return this.partsOf(skill.stage).find(p => p.skills.includes(skill))?.n || 1;
  }
  /** Unlocked when every prerequisite is passed or was skipped on purpose. */
  isUnlocked(skill, states, skipped = new Set()) {
    return (skill.prerequisites || []).every(p => skipped.has(p) || Comprehension.isPassed(states[p]));
  }
}

// ---------- Skill picker ----------
const ReasonLabel = { repair: "Fixing a gap", review: "Memory review", advance: "New skill", done: "All caught up" };

class SkillPicker {
  constructor(graph) { this.graph = graph; }

  /** excluding: skills to leave out (skipped for good or for this session).
      skipped: skills skipped for good; they count as done for unlocking what builds on them. */
  next(states, now = Date.now(), excluding = new Set(), skipped = new Set()) {
    const st = id => states[id] || newSkillState();
    const practicable = this.graph.ordered.filter(s => hasPractice(s) && !excluding.has(s.id));

    const weak = practicable.filter(s => {
      const x = st(s.id);
      return x.attempts >= 3 && !x.provisional && x.comprehension < Comprehension.passThreshold;
    });
    if (weak.length) {
      let worst = weak[0];
      for (const s of weak) if (this.priority(s, states) > this.priority(worst, states)) worst = s;
      return { skill: this.deepestWeakRoot(worst, states, excluding), reason: "repair" };
    }

    const due = practicable.filter(s => SpacedReview.isDue(st(s.id), now))
      .sort((a, b) => (st(a.id).nextReview ?? now) - (st(b.id).nextReview ?? now));
    if (due.length) return { skill: due[0], reason: "review" };

    const unlocked = practicable.filter(s => this.graph.isUnlocked(s, states, skipped));
    const inProgress = unlocked.find(s => {
      const x = st(s.id), l = Comprehension.level(x);
      return x.attempts > 0 && (l === "learning" || l === "passing");
    });
    if (inProgress) return { skill: inProgress, reason: "advance" };
    const fresh = unlocked.find(s => Comprehension.level(st(s.id)) === "new");
    if (fresh) return { skill: fresh, reason: "advance" };
    return { skill: null, reason: "done" };
  }

  priority(skill, states) {
    const c = states[skill.id]?.comprehension ?? 0;
    return ((this.graph.impact[skill.id] ?? 0) + 1) * (1 - c);
  }

  deepestWeakRoot(skill, states, excluding) {
    let current = skill;
    const visited = new Set();
    while (!visited.has(current.id)) {
      visited.add(current.id);
      const w = (current.prerequisites || []).map(id => this.graph.skill(id)).filter(Boolean)
        .filter(s => hasPractice(s) && !excluding.has(s.id))
        .find(s => {
          const x = states[s.id] || newSkillState();
          return x.attempts > 0 && x.comprehension < Comprehension.passThreshold;
        });
      if (!w) break;
      current = w;
    }
    return current;
  }

  biggestGaps(states, limit = 5) {
    return this.graph.curriculum.skills
      .filter(s => {
        const x = states[s.id] || newSkillState();
        return x.attempts >= 3 && !x.provisional && x.comprehension < Comprehension.passThreshold;
      })
      .sort((a, b) => this.priority(b, states) - this.priority(a, states))
      .slice(0, limit);
  }
}

// ---------- Placement test ----------
class Diagnostic {
  constructor(graph, questionsPerStage = 4) {
    this.graph = graph;
    this.questionsPerStage = questionsPerStage;
    this.stages = graph.stagesSorted;
    this.stageIndex = 0;
    this.finished = false;
    this.passedStages = [];
    this.stageResults = [];
    this.stageQueue = [];
    this.loadStage();
  }
  get currentStage() { return this.stages[this.stageIndex] || null; }
  nextSkill() {
    while (!this.finished && this.stageQueue.length === 0) this.skipStage();
    if (this.finished) return null;
    return this.stageQueue[this.stageResults.length % this.stageQueue.length];
  }
  skipStage() {
    this.stageIndex += 1;
    if (this.stageIndex >= this.stages.length) this.finished = true; else this.loadStage();
  }
  record(skill, correct, seconds) {
    const pace = skill.sightPaceSeconds ?? Comprehension.defaultSightPace;
    this.stageResults.push(correct && seconds <= pace * 3);
    if (this.stageResults.length >= this.questionsPerStage) {
      const passes = this.stageResults.filter(Boolean).length;
      this.advance(passes / this.questionsPerStage >= 0.75);
    }
  }
  apply(states) {
    const out = { ...states };
    for (const stageId of this.passedStages) {
      for (const skill of this.graph.skillsIn(stageId)) {
        const s = { ...newSkillState(), ...(out[skill.id] || {}) };
        if (s.attempts !== 0) continue;
        s.comprehension = Comprehension.masteryThreshold;
        s.provisional = true;
        s.tier = 3;
        out[skill.id] = s;
      }
    }
    return out;
  }
  advance(passed) {
    if (passed && this.currentStage) {
      this.passedStages.push(this.currentStage.id);
      this.stageIndex += 1;
      if (this.stageIndex >= this.stages.length) this.finished = true; else this.loadStage();
    } else {
      this.finished = true;
    }
  }
  loadStage() {
    this.stageResults = [];
    const stage = this.currentStage;
    if (!stage) { this.finished = true; return; }
    const skills = this.graph.skillsIn(stage.id).filter(hasPractice);
    const generated = skills.filter(s => s.practice.generator);
    const pool = generated.length ? generated : skills;
    if (pool.length <= this.questionsPerStage) this.stageQueue = pool;
    else {
      const step = pool.length / this.questionsPerStage;
      this.stageQueue = Array.from({ length: this.questionsPerStage }, (_, i) => pool[Math.floor(i * step)]);
    }
  }
}

// ---------- Answer checking ----------
const AnswerChecker = {
  matches(given, expected) {
    const g = this.normalize(given), e = this.normalize(expected);
    if (g === e) return true;
    const a = this.number(g), b = this.number(e);
    return a != null && b != null && Math.abs(a - b) < 1e-9;
  },
  normalize(s) {
    return String(s).toLowerCase().replace(/ /g, "").replace(/−/g, "-").replace(/,/g, "").trim();
  },
  number(s) {
    if (/^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/.test(s)) return Number(s);
    const parts = s.split("/");
    if (parts.length === 2) {
      const n = this.number(parts[0]), d = this.number(parts[1]);
      if (n != null && d != null && d !== 0) return n / d;
    }
    return null;
  },
};

// ---------- Dice ----------
const Dice = {
  int(lo, hi) { return lo >= hi ? lo : lo + Math.floor(Math.random() * (hi - lo + 1)); },
  bool() { return Math.random() < 0.5; },
  pick(items) { return items[this.int(0, items.length - 1)]; },
  shuffled(items) {
    const a = [...items];
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  },
};

// ---------- Question generators ----------
const G = {
  gcd(a, b) { return b === 0 ? Math.abs(a) : G.gcd(b, a % b); },
  choose(n, k) {
    if (k < 0 || k > n) return 0;
    let r = 1;
    for (let i = 0; i < Math.min(k, n - k); i++) r = r * (n - i) / (i + 1);
    return Math.round(r);
  },
  term(c, v) { return c === 1 ? v : c === -1 ? `-${v}` : `${c}${v}`; },
  signedTerm(c, v) {
    if (c === 0) return "";
    const body = Math.abs(c) === 1 ? v : `${Math.abs(c)}${v}`;
    return c > 0 ? ` + ${body}` : ` − ${body}`;
  },
  signed(n) { return n === 0 ? "" : n > 0 ? ` + ${n}` : ` − ${-n}`; },
  tenths(t) { return `${Math.trunc(t / 10)}.${t % 10}`; },
  half(a, d) { return a % d === 0 ? `${a / d}` : `${a / G.gcd(a, d)}/${d / G.gcd(a, d)}`; },
  sub(n) { return String(n).replace(/\d/g, c => "₀₁₂₃₄₅₆₇₈₉"[c]); },
  mod(a, n) { return ((a % n) + n) % n; },
};

// Size settings each generator uses, with its defaults. Starter and Core shrink these;
// Challenge uses the skill's own settings (the full skill).
const GeneratorSizes = {
  count: { max: 20 }, countBy: { max: 100 }, numberAfter: { max: 120 }, compare: { max: 100 },
  placeValue: { digits: 2 }, tenMore: { max: 100 }, evenOdd: { max: 50 }, roundTen: { max: 100 },
  add: { max: 10 }, add3: { max: 9 }, sub: { max: 10 }, missingAddend: { max: 10 }, doubles: { max: 10 },
  factFamily: { max: 10 }, wordAdd: { max: 10 }, mul: { max: 10 }, div: { max: 10 }, fractionOf: { maxDen: 10 },
  fractionAdd: { maxDen: 12 }, integerAdd: { max: 20 }, integerMul: { max: 12 }, exponent: { maxBase: 6 },
  sqrt: { max: 15 }, linearEq: { max: 10 }, binomial: { max: 10 }, mod: { max: 13 }, gcd: { max: 12 }, lcm: { max: 15 },
};

function tierParams(key, params, tier) {
  const out = { ...(params || {}) };
  if (tier >= 3) return out;
  const sizes = GeneratorSizes[key] || {};
  for (const [name, fallback] of Object.entries(sizes)) {
    const full = out[name] ?? fallback;
    if (name === "digits") { out.digits = Math.max(2, full - (3 - tier)); continue; }
    let floor = name === "max" ? 3 : 2;
    if (key === "countBy") floor = Math.max(floor, (out.step || 1) * 4);
    if (out.min != null) floor = Math.max(floor, out.min + 1);
    out[name] = Math.min(full, Math.max(floor, Math.round(full * (tier === 1 ? 0.4 : 0.7))));
  }
  return out;
}

function makeGenerated(key, params, skillId, tier = 3) {
  const d = Dice;
  const p = (name, fb) => (params && params[name] != null ? params[name] : fb);
  // Every generated question carries "why": a short explanation shown after any answer.
  const q = (prompt, answer, why) => ({ skillId, prompt, answer: String(answer), why });
  const mc = (prompt, choices, answer, why) => ({ skillId, prompt, choices, answer, why });
  const list = (from, to, step = 1) => { const out = []; for (let i = from; step > 0 ? i <= to : i >= to; i += step) out.push(i); return out; };
  const countOn = (a, b) => b === 0 ? `Adding 0 leaves ${a} the same.` : b <= 6 ? `Start at ${a} and count on ${b}: ${list(a + 1, a + b).join(", ")}.` : `Make a ten or add in parts: ${a} + ${b} = ${a + b}.`;

  switch (key) {
    // Counting and number sense
    case "count": {
      const n = d.int(1, p("max", 20));
      const dots = Array.from({ length: n }, (_, i) => (i > 0 && i % 5 === 0 ? " ●" : "●")).join("");
      const groups = Math.floor(n / 5), rest = n % 5;
      const why = n > 5 ? `The dots come in groups of 5. ${groups} group${groups > 1 ? "s" : ""} of 5 is ${groups * 5}${rest ? `, plus ${rest} more makes ${n}` : ""}.` : `Touch each dot once and count: ${list(1, n).join(", ")}. The last number said is ${n}.`;
      return q(`How many dots?\n${dots}`, n, why);
    }
    case "countBy": {
      const step = p("step", 1);
      const start = step * d.int(0, Math.max(0, Math.floor(p("max", 100) / step) - 3));
      return q(`What comes next?\n${start}, ${start + step}, ${start + 2 * step}, __`, start + 3 * step,
        `Each number is ${step} more than the one before. ${start + 2 * step} + ${step} = ${start + 3 * step}.`);
    }
    case "numberAfter": {
      const n = d.int(1, p("max", 120));
      return d.bool() ? q(`What number comes just after ${n}?`, n + 1, `Just after means 1 more: ${n} + 1 = ${n + 1}.`)
                      : q(`What number comes just before ${n}?`, n - 1, `Just before means 1 less: ${n} − 1 = ${n - 1}.`);
    }
    case "compare": {
      const a = d.int(0, p("max", 100));
      let b = d.int(0, p("max", 100));
      if (d.int(0, 5) === 0) b = a;
      const why = a === b ? `Both numbers are ${a}, so they are equal: ${a} = ${b}.`
        : `${Math.max(a, b)} is bigger than ${Math.min(a, b)}. The open side of the sign faces the bigger number: ${a} ${a > b ? ">" : "<"} ${b}.`;
      return mc(`Which sign goes in the blank?\n${a} __ ${b}`, [">", "<", "="], a > b ? ">" : a < b ? "<" : "=", why);
    }
    case "placeValue": {
      const digits = Math.max(2, Math.min(4, p("digits", 2)));
      const n = d.int(10 ** (digits - 1), 10 ** digits - 1);
      const places = ["ones", "tens", "hundreds", "thousands"];
      const i = d.int(0, digits - 1);
      const digit = Math.floor(n / 10 ** i) % 10;
      const order = places.slice(0, digits).reverse().join(", ");
      return q(`What digit is in the ${places[i]} place of ${n}?`, digit,
        `Reading ${n} from left to right, the places are ${order}. The ${places[i]} digit is ${digit}.`);
    }
    case "tenMore": {
      const n = d.int(10, Math.max(10, p("max", 100) - 10));
      return d.bool() ? q(`What is 10 more than ${n}?`, n + 10, `10 more changes only the tens digit, up by 1: ${n} → ${n + 10}.`)
                      : q(`What is 10 less than ${n}?`, n - 10, `10 less changes only the tens digit, down by 1: ${n} → ${n - 10}.`);
    }
    case "evenOdd": {
      const n = d.int(0, p("max", 50));
      const even = n % 2 === 0;
      return mc(`Is ${n} even or odd?`, ["Even", "Odd"], even ? "Even" : "Odd",
        `Look at the last digit, ${n % 10}. ${even ? "0, 2, 4, 6 and 8 make a number even: it splits into two equal groups." : "1, 3, 5, 7 and 9 make a number odd: one is left over when you make pairs."}`);
    }
    case "roundTen": {
      const n = d.int(0, p("max", 100));
      const r = Math.round(n / 10) * 10, ones = n % 10;
      return q(`Round ${n} to the nearest ten.`, r,
        `${n} is between ${n - ones} and ${n - ones + 10}. The ones digit is ${ones}, ${ones >= 5 ? "5 or more, so round up" : "less than 5, so round down"} to ${r}.`);
    }

    // Addition and subtraction
    case "add": { const m = p("max", 10), a = d.int(0, m), b = d.int(0, m); return q(`${a} + ${b} = ?`, a + b, countOn(Math.max(a, b), Math.min(a, b)) + (a < b && a > 0 ? ` (Starting from the bigger number is faster.)` : "")); }
    case "add3": {
      const m = p("max", 9), a = d.int(0, m), b = d.int(0, m), c = d.int(0, m);
      return q(`${a} + ${b} + ${c} = ?`, a + b + c, `Add two at a time: ${a} + ${b} = ${a + b}, then ${a + b} + ${c} = ${a + b + c}.`);
    }
    case "sub": {
      const a = d.int(0, p("max", 10)), b = d.int(0, a);
      return q(`${a} − ${b} = ?`, a - b, b === 0 ? `Taking away 0 leaves ${a}.` : `Start at ${b} and count up to ${a}. That is ${a - b} steps, so ${a} − ${b} = ${a - b}. Check: ${a - b} + ${b} = ${a}.`);
    }
    case "missingAddend": {
      const c = d.int(0, p("max", 10)), a = d.int(0, c);
      return q(`${a} + ? = ${c}`, c - a, `Count up from ${a} to ${c}: that is ${c - a}. Check: ${a} + ${c - a} = ${c}.`);
    }
    case "makeTen": { const a = d.int(0, 10); return q(`${a} + ? = 10`, 10 - a, `${a} and ${10 - a} are partners that make 10. On a ten frame, ${a} filled leaves ${10 - a} empty.`); }
    case "doubles": { const n = d.int(0, p("max", 10)); return q(`${n} + ${n} = ?`, 2 * n, `A double is the same number twice. ${n} + ${n} = ${2 * n}${n <= 5 ? ` (like ${n} fingers on each hand)` : ""}.`); }
    case "factFamily": {
      const m = p("max", 10), a = d.int(1, m), b = d.int(1, m);
      return q(`If ${a} + ${b} = ${a + b}, what is ${a + b} − ${b}?`, a,
        `${a}, ${b} and ${a + b} are a fact family. Taking ${b} back away from ${a + b} leaves ${a}.`);
    }
    case "wordAdd": {
      const m = p("max", 10), a = d.int(1, m), b = d.int(1, m);
      const thing = d.pick(["apples", "stickers", "blocks", "shells", "crayons"]);
      if (d.bool()) return q(`Sam has ${a} ${thing}. Sam gets ${b} more. How many ${thing} now?`, a + b, `"Gets more" means add: ${a} + ${b} = ${a + b} ${thing}.`);
      return q(`Sam has ${a + b} ${thing}. Sam gives away ${b}. How many ${thing} are left?`, a, `"Gives away" means subtract: ${a + b} − ${b} = ${a} ${thing}.`);
    }
    case "money": {
      // Starter: dimes and pennies only. Core adds nickels. Challenge adds quarters.
      const qu = tier >= 3 ? d.int(0, 3) : 0, di = d.int(0, 4), ni = tier >= 2 ? d.int(0, 3) : 0, pe = d.int(0, 4);
      const coins = [[qu, "quarter", "quarters", 25], [di, "dime", "dimes", 10], [ni, "nickel", "nickels", 5], [pe, "penny", "pennies", 1]].filter(c => c[0] > 0);
      if (!coins.length) return q("How many cents is 1 dime?", 10, "A dime is worth 10 cents.");
      const parts = coins.map(c => (c[0] === 1 ? `1 ${c[1]}` : `${c[0]} ${c[2]}`));
      const total = qu * 25 + di * 10 + ni * 5 + pe;
      const steps = coins.map(c => `${c[0] === 1 ? `1 ${c[1]}` : `${c[0]} ${c[2]}`} = ${c[0] * c[3]}¢`).join(", ");
      return q(`How many cents?\n${parts.join(", ")}`, total, `Count the biggest coins first. ${steps}. Together that is ${total} cents.`);
    }
    case "time": {
      const h = d.int(1, 12);
      if (tier === 1 || d.bool()) return q(`The short hand points to ${h}. The long hand points to 12. What time is it?`, `${h}:00`,
        `The short hand tells the hour: ${h}. The long hand on 12 means exactly on the hour, so it is ${h}:00 (${h} o'clock).`);
      const nh = h === 12 ? 1 : h + 1;
      return q(`The short hand is between ${h} and ${nh}. The long hand points to 6. What time is it?`, `${h}:30`,
        `The hour is the number the short hand has passed: ${h}. The long hand on 6 means half past, 30 minutes. So it is ${h}:30.`);
    }

    // Multiplication, division, fractions, decimals
    case "mul": {
      const a = d.int(p("min", 0), p("max", 10)), b = d.int(p("min", 0), p("max", 10));
      const why = a === 0 || b === 0 ? `Anything times 0 is 0.` : `${a} × ${b} means ${b} groups of ${a}${b <= 5 ? `: ${Array(b).fill(a).join(" + ")} = ${a * b}` : ` = ${a * b}`}.`;
      return q(`${a} × ${b} = ?`, a * b, why);
    }
    case "div": {
      const b = d.int(1, p("max", 10)), x = d.int(0, p("max", 10));
      return q(`${b * x} ÷ ${b} = ?`, x, `Think: what times ${b} makes ${b * x}? ${x} × ${b} = ${b * x}, so ${b * x} ÷ ${b} = ${x}.`);
    }
    case "orderOps": {
      const a = d.int(1, 9), b = d.int(1, 9), c = d.int(1, 9);
      return d.bool() ? q(`${a} + ${b} × ${c} = ?`, a + b * c, `Multiply before adding: ${b} × ${c} = ${b * c}, then ${a} + ${b * c} = ${a + b * c}.`)
                      : q(`(${a} + ${b}) × ${c} = ?`, (a + b) * c, `Parentheses come first: ${a} + ${b} = ${a + b}, then ${a + b} × ${c} = ${(a + b) * c}.`);
    }
    case "fractionOf": {
      const den = d.int(2, p("maxDen", 10)), n = den * d.int(1, 10);
      return q(`What is 1/${den} of ${n}?`, n / den, `1/${den} means split into ${den} equal groups. ${n} ÷ ${den} = ${n / den}.`);
    }
    case "fractionAdd": {
      const den = d.int(2, p("maxDen", 12)), a = d.int(1, den), b = d.int(1, den);
      return q(`${a}/${den} + ${b}/${den} = ?`, `${a + b}/${den}`, `The pieces are the same size (${den}ths), so add the tops and keep the bottom: ${a} + ${b} = ${a + b}, giving ${a + b}/${den}.`);
    }
    case "fractionCompare": {
      const d1 = d.int(2, 12), d2 = d.int(2, 12), n1 = d.int(1, d1), n2 = d.int(1, d2);
      if (n1 * d2 === n2 * d1) return mc("Which is greater?", [`${n1}/${d1}`, `${n1 + 1}/${d1}`], `${n1 + 1}/${d1}`, `Same bottom number, so the one with more pieces is bigger: ${n1 + 1} pieces beats ${n1}.`);
      const big = n1 * d2 > n2 * d1 ? `${n1}/${d1}` : `${n2}/${d2}`;
      return mc("Which is greater?", [`${n1}/${d1}`, `${n2}/${d2}`], big,
        `Cross-multiply to compare: ${n1} × ${d2} = ${n1 * d2} and ${n2} × ${d1} = ${n2 * d1}. The larger product belongs to ${big}.`);
    }
    case "decimalAdd": {
      const a = d.int(1, 99), b = d.int(1, 99);
      return q(`${G.tenths(a)} + ${G.tenths(b)} = ?`, G.tenths(a + b), `Line up the decimal points and add tenths: ${a} tenths + ${b} tenths = ${a + b} tenths = ${G.tenths(a + b)}.`);
    }
    case "percent": {
      const pct = d.pick([10, 20, 25, 50, 75]), n = 20 * d.int(1, 10);
      return q(`What is ${pct}% of ${n}?`, pct * n / 100, `${pct}% means ${pct} out of 100, which is ${pct}/100. ${n} × ${pct} ÷ 100 = ${pct * n / 100}.`);
    }

    // Integers, powers, roots
    case "integerAdd": {
      const m = p("max", 20), a = d.int(-m, m), b = d.int(-m, m);
      const why = (a >= 0) === (b >= 0) ? `Same signs: add the sizes (${Math.abs(a)} + ${Math.abs(b)} = ${Math.abs(a) + Math.abs(b)}) and keep the sign. Answer: ${a + b}.`
        : `Different signs: subtract the sizes (${Math.max(Math.abs(a), Math.abs(b))} − ${Math.min(Math.abs(a), Math.abs(b))} = ${Math.abs(a + b)}) and take the sign of the bigger size. Answer: ${a + b}.`;
      return q(`(${a}) + (${b}) = ?`, a + b, why);
    }
    case "integerMul": {
      const m = p("max", 12), a = d.int(-m, m), b = d.int(-m, m);
      const why = a === 0 || b === 0 ? "Anything times 0 is 0." : `${Math.abs(a)} × ${Math.abs(b)} = ${Math.abs(a * b)}. ${(a < 0) === (b < 0) ? "Same signs give a positive answer" : "Different signs give a negative answer"}: ${a * b}.`;
      return q(`(${a}) × (${b}) = ?`, a * b, why);
    }
    case "exponent": {
      const base = d.int(2, p("maxBase", 6)), e = d.int(2, base <= 3 ? 5 : 3);
      return q(`${base}^${e} = ?`, base ** e, `${base}^${e} means ${e} copies of ${base} multiplied: ${Array(e).fill(base).join(" × ")} = ${base ** e}.`);
    }
    case "sqrt": { const n = d.int(1, p("max", 15)); return q(`√${n * n} = ?`, n, `The square root asks which number times itself gives ${n * n}. ${n} × ${n} = ${n * n}.`); }

    // Algebra
    case "linearEq": {
      const m = p("max", 10);
      let a = d.int(1, 9); if (d.bool()) a = -a;
      const x = d.int(-m, m), b = d.int(-m, m), rhs = a * x + b;
      const step1 = b === 0 ? `${G.term(a, "x")} = ${rhs}` : `${b > 0 ? "Subtract" : "Add"} ${Math.abs(b)} on both sides: ${G.term(a, "x")} = ${rhs - b}`;
      return q(`Solve for x:\n${G.term(a, "x")}${G.signed(b)} = ${rhs}`, x,
        `${step1}. ${a === 1 ? "" : `Divide both sides by ${a}: `}x = ${x}. Check: ${a} × ${x}${G.signed(b)} = ${rhs}.`);
    }
    case "proportion": {
      const a = d.int(1, 9), b = d.int(2, 9), k = d.int(2, 6);
      return q(`${a}/${b} = x/${b * k}. What is x?`, a * k, `The bottom went from ${b} to ${b * k}, which is × ${k}. Do the same to the top: ${a} × ${k} = ${a * k}.`);
    }
    case "slope": {
      const x1 = d.int(-5, 5), dx = d.int(1, 5), m = d.int(-4, 4), y1 = d.int(-5, 5), y2 = y1 + m * dx;
      return q(`What is the slope of the line through (${x1}, ${y1}) and (${x1 + dx}, ${y2})?`, m,
        `Slope = rise ÷ run = (${y2} − ${y1}) ÷ (${x1 + dx} − ${x1}) = ${y2 - y1} ÷ ${dx} = ${m}.`);
    }
    case "evalPoly": {
      const a = d.int(1, 4), b = d.int(-5, 5), c = d.int(-9, 9), k = d.int(-3, 3);
      return q(`f(x) = ${G.term(a, "x²")}${G.signedTerm(b, "x")}${G.signed(c)}. What is f(${k})?`, a * k * k + b * k + c,
        `Put ${k} in for x: ${a}(${k})² + ${b}(${k}) + ${c} = ${a * k * k} + ${b * k} + ${c} = ${a * k * k + b * k + c}.`);
    }
    case "quadraticRoots": {
      const r = d.int(-9, 9); let s = d.int(-9, 9); if (s === r) s += 1;
      return q(`Solve x²${G.signedTerm(-(r + s), "x")}${G.signed(r * s)} = 0.\nGive the larger solution.`, Math.max(r, s),
        `Find two numbers that multiply to ${r * s} and add to ${r + s}: ${r} and ${s}. So (x${G.signed(-r)})(x${G.signed(-s)}) = 0 and x = ${r} or x = ${s}. The larger is ${Math.max(r, s)}.`);
    }

    // Statistics and probability
    case "mean": {
      const n = tier === 1 ? 3 : d.int(3, 5);
      const values = Array.from({ length: n - 1 }, () => d.int(1, 20));
      const target = d.int(5, 15);
      values.push(target * n - values.reduce((a, b) => a + b, 0));
      if (values[values.length - 1] < 0) return q("Mean of 2, 4, 6?", 4, "Add them: 2 + 4 + 6 = 12. Divide by how many (3): 12 ÷ 3 = 4.");
      const shown = d.shuffled(values);
      return q(`What is the mean of ${shown.join(", ")}?`, target, `Add them: ${shown.join(" + ")} = ${target * n}. Divide by how many (${n}): ${target * n} ÷ ${n} = ${target}.`);
    }
    case "median": {
      const values = Array.from({ length: tier === 1 ? 3 : 2 * d.int(1, 3) + 1 }, () => d.int(1, 50));
      const sorted = [...values].sort((a, b) => a - b), mid = sorted[Math.floor(values.length / 2)];
      return q(`What is the median of ${values.join(", ")}?`, mid, `Put them in order: ${sorted.join(", ")}. The middle one is ${mid}.`);
    }
    case "probabilityDie": {
      const k = d.int(1, 5);
      return q(`A fair die is rolled. What is the probability of rolling a number greater than ${k}? (fraction)`, `${6 - k}/6`,
        `The numbers greater than ${k} are ${list(k + 1, 6).join(", ")}: ${6 - k} of the 6 equally likely sides. So ${6 - k}/6.`);
    }
    case "binomial": {
      const n = d.int(2, p("max", 10)), k = d.int(0, n);
      return q(`How many ways to choose ${k} items from ${n}? (${n} choose ${k})`, G.choose(n, k),
        k === 0 || k === n ? `There is only 1 way to choose ${k === 0 ? "none" : "all of them"}.` : `${n} choose ${k} = ${n}! ÷ (${k}! × ${n - k}!) = ${G.choose(n, k)}. (n! means n × (n − 1) × … × 1.)`);
    }

    // Number theory
    case "gcd": {
      const m = p("max", 12), g = d.int(1, m), a = g * d.int(1, m), b = g * d.int(1, m), ans = G.gcd(a, b);
      return q(`gcd(${a}, ${b}) = ?`, ans, `${ans} divides both: ${a} = ${ans} × ${a / ans} and ${b} = ${ans} × ${b / ans}. ${a / ans} and ${b / ans} share no other factor, so ${ans} is the greatest.`);
    }
    case "lcm": {
      const m = p("max", 15), a = d.int(2, m), b = d.int(2, m), ans = a / G.gcd(a, b) * b;
      return q(`lcm(${a}, ${b}) = ?`, ans, `Count up by ${Math.max(a, b)}s until you reach a number ${Math.min(a, b)} divides: ${ans} = ${a} × ${ans / a} = ${b} × ${ans / b}.`);
    }
    case "mod": {
      const n = d.int(2, p("max", 13)), a = d.int(0, 200);
      return q(`${a} mod ${n} = ?`, a % n, `${a} = ${Math.floor(a / n)} × ${n} + ${a % n}. The remainder is ${a % n}.`);
    }
    case "modInverse": {
      const prime = d.pick([5, 7, 11, 13]), a = d.int(1, prime - 1);
      let inv = 1; for (let i = 1; i < prime; i++) if ((a * i) % prime === 1) { inv = i; break; }
      return q(`Find the inverse of ${a} modulo ${prime} (a number from 1 to ${prime - 1}).`, inv,
        `The inverse times ${a} leaves remainder 1: ${a} × ${inv} = ${a * inv} = ${Math.floor(a * inv / prime)} × ${prime} + 1.`);
    }
    case "eulerPhi": {
      const n = d.int(2, 40);
      const co = list(1, n).filter(i => G.gcd(i, n) === 1);
      return q(`φ(${n}) = ? (how many numbers from 1 to ${n} share no factor with ${n})`, co.length,
        co.length <= 16 ? `They are ${co.join(", ")}: ${co.length} numbers.` : `Count the numbers from 1 to ${n} that share no factor with ${n}: there are ${co.length}.`);
    }
    case "groupOrder": {
      const n = d.int(4, 24), k = d.int(1, n - 1), g = G.gcd(n, k);
      return q(`In the group ℤ${G.sub(n)} under addition, what is the order of ${k}?`, n / g,
        `The order is how many times you add ${k} to get back to 0 (mod ${n}). That is ${n} ÷ gcd(${n}, ${k}) = ${n} ÷ ${g} = ${n / g}.`);
    }

    // Calculus and series
    case "logBase": {
      const base = d.pick([2, 3, 5, 10]), e = d.int(0, 4);
      return q(`log base ${base} of ${base ** e} = ?`, e, e === 0 ? `Any base to the power 0 is 1, so the answer is 0.` : `${base} to the power ${e} is ${base ** e} (${Array(e).fill(base).join(" × ")}), so the logarithm is ${e}.`);
    }
    case "derivative": {
      const a = d.int(1, 5), n = d.int(2, 4), b = d.int(-6, 6), k = d.int(-2, 2);
      return q(`f(x) = ${G.term(a, `x^${n}`)}${G.signedTerm(b, "x")}. What is f′(${k})?`, a * n * k ** (n - 1) + b,
        `Power rule: bring the power down and lower it by 1. f′(x) = ${a * n}x^${n - 1}${G.signed(b)}. At x = ${k}: ${a * n} × ${k ** (n - 1)}${G.signed(b)} = ${a * n * k ** (n - 1) + b}.`);
    }
    case "integral": {
      const a = d.int(1, 6), k = d.int(1, 5);
      return q(`Evaluate the integral from 0 to ${k} of ${2 * a}x dx.`, a * k * k, `An antiderivative of ${2 * a}x is ${G.term(a, "x²")}. Evaluate from 0 to ${k}: ${a} × ${k * k} − 0 = ${a * k * k}.`);
    }
    case "limit": {
      const a = d.int(-6, 6);
      return q(`lim as x → ${a} of (x² − ${a * a}) / (x${G.signed(-a)}) = ?`, 2 * a,
        `Factor the top: x² − ${a * a} = (x${G.signed(-a)})(x${G.signed(a)}). Cancel (x${G.signed(-a)}) to get x${G.signed(a)}, then put in x = ${a}: ${2 * a}.`);
    }
    case "geometricSeries": {
      const a = d.int(1, 20) * 2;
      return q(`${a} + ${a / 2} + ${G.half(a, 4)} + ${G.half(a, 8)} + … (forever) = ?`, 2 * a,
        `Each term is half the one before. A geometric series with first term ${a} and ratio 1/2 adds up to ${a} ÷ (1 − 1/2) = ${2 * a}.`);
    }

    // Linear algebra and complex numbers
    case "det2": {
      const v = Array.from({ length: 4 }, () => d.int(-6, 6));
      return q(`det [[${v[0]}, ${v[1]}], [${v[2]}, ${v[3]}]] = ?`, v[0] * v[3] - v[1] * v[2],
        `ad − bc = (${v[0]})(${v[3]}) − (${v[1]})(${v[2]}) = ${v[0] * v[3]} − ${v[1] * v[2]} = ${v[0] * v[3] - v[1] * v[2]}.`);
    }
    case "dot": {
      const u = Array.from({ length: 3 }, () => d.int(-5, 5)), w = Array.from({ length: 3 }, () => d.int(-5, 5));
      const prods = u.map((x, i) => x * w[i]);
      return q(`(${u.join(", ")}) · (${w.join(", ")}) = ?`, prods.reduce((s, x) => s + x, 0),
        `Multiply matching parts and add: ${u.map((x, i) => `(${x})(${w[i]})`).join(" + ")} = ${prods.join(" + ")} = ${prods.reduce((s, x) => s + x, 0)}.`);
    }
    case "eigenTriangular": {
      const a = d.int(-6, 6), b = d.int(-6, 6); let dd = d.int(-6, 6); if (dd === a) dd += 1;
      return q(`The matrix [[${a}, ${b}], [0, ${dd}]] has two eigenvalues. What is the larger one?`, Math.max(a, dd),
        `For a triangular matrix the eigenvalues are the numbers on the diagonal: ${a} and ${dd}. The larger is ${Math.max(a, dd)}.`);
    }
    case "complexModulus": {
      const t = d.pick([[3, 4, 5], [5, 12, 13], [6, 8, 10], [8, 15, 17], [7, 24, 25]]);
      return q(`|${t[0]} + ${t[1]}i| = ?`, t[2], `The size of a + bi is √(a² + b²) = √(${t[0] ** 2} + ${t[1] ** 2}) = √${t[2] ** 2} = ${t[2]}.`);
    }

    default: return null;
  }
}

// ---------- Question factory ----------
class QuestionFactory {
  constructor() { this.recent = {}; }
  question(skill, tier = 3) {
    if (skill.practice?.generator) {
      const key = skill.practice.generator;
      const g = makeGenerated(key, tierParams(key, skill.practice.params, tier), skill.id, tier);
      if (g) return { ...g, tier };
    }
    const all = skill.practice?.items || [];
    if (!all.length) return null;
    // Items for this tier; if none, the closest tier (easier first). Untagged items fit any tier.
    let items = [];
    for (const t of [tier, tier - 1, tier + 1, tier - 2, tier + 2]) {
      items = all.filter(i => i.tier == null || i.tier === t);
      if (items.length) break;
    }
    const recent = this.recent[skill.id] || [];
    const fresh = items.filter(i => !recent.includes(i.prompt));
    const item = Dice.pick(fresh.length ? fresh : items);
    const updated = [...recent, item.prompt];
    if (updated.length > Math.max(1, items.length - 1)) updated.shift();
    this.recent[skill.id] = updated;
    return {
      skillId: skill.id,
      prompt: item.prompt,
      choices: item.choices ? Dice.shuffled(item.choices) : null,
      answer: item.answer ?? null,
      tutorJudged: item.mode === "tutor",
      why: item.why || null,
      tier,
    };
  }
}

function checkAnswer(question, given) {
  return question.answer != null && AnswerChecker.matches(given, question.answer);
}

// ---------- Profiles (saved in this browser) ----------
const STORE_KEY = "tutor.profiles.v1";

function uuid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return "p-" + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
}

const ProfileStore = {
  profiles: [],
  available: true,
  load() {
    try {
      const raw = localStorage.getItem(STORE_KEY);
      this.profiles = raw ? JSON.parse(raw) : [];
    } catch (e) {
      this.profiles = [];
      this.available = false;
    }
  },
  save() {
    try { localStorage.setItem(STORE_KEY, JSON.stringify(this.profiles)); this.available = true; }
    catch (e) { this.available = false; }
  },
  get(id) { return this.profiles.find(p => p.id === id); },
  add(name) {
    const p = { id: uuid(), name, createdAt: Date.now(), progress: {}, currentDay: {}, sessions: [] };
    this.profiles.push(p);
    this.save();
    return p;
  },
  remove(id) { this.profiles = this.profiles.filter(p => p.id !== id); this.save(); },
  exportText() {
    return JSON.stringify({ kind: "tutor-progress", version: 1, exportedAt: new Date().toISOString(), profiles: this.profiles }, null, 1);
  },
  // Merge a backup in: learners with the same id are replaced, new ones added.
  importText(text) {
    const data = JSON.parse(text);
    const list = Array.isArray(data) ? data : data.profiles;
    if (!Array.isArray(list)) throw new Error("That text isn't a progress backup.");
    let count = 0;
    for (const p of list) {
      if (!p || !p.id || !p.name) continue;
      const clean = { progress: {}, currentDay: {}, sessions: [], createdAt: Date.now(), ...p };
      const i = this.profiles.findIndex(x => x.id === p.id);
      if (i >= 0) this.profiles[i] = clean; else this.profiles.push(clean);
      count++;
    }
    this.save();
    return count;
  },
};

// Skills a tutor chose to skip, per learner and curriculum. The app stops picking them,
// and skills that build on them stay unlocked. Undo any time from the skill's page.
function skippedSet(profile, curriculumId) {
  return new Set(profile.skipped?.[curriculumId] || []);
}
function setSkipped(profile, curriculumId, skillId, on) {
  const set = skippedSet(profile, curriculumId);
  if (on) set.add(skillId); else set.delete(skillId);
  profile.skipped = { ...(profile.skipped || {}), [curriculumId]: [...set] };
  ProfileStore.save();
}

function stateOf(profile, curriculumId, skillId) {
  return profile.progress?.[curriculumId]?.[skillId] || newSkillState();
}
function statesOf(profile, curriculumId) { return profile.progress?.[curriculumId] || {}; }

function studySecondsOn(profile, day = new Date()) {
  const start = new Date(day); start.setHours(0, 0, 0, 0);
  const end = start.getTime() + DAY_MS;
  return (profile.sessions || [])
    .filter(s => s.startedAt >= start.getTime() && s.startedAt < end)
    .reduce((t, s) => t + (s.activeSeconds || 0), 0);
}

// ---------- Practice session ----------
// mode: {type:"adaptive"} | {type:"focus", skillIds, reviewCount} | {type:"diagnostic"}
// The placement test asks Challenge questions; practice asks at the learner's tier.
class PracticeSession {
  constructor(curriculum, graph, profile, mode, goal = 20) {
    this.curriculum = curriculum;
    this.graph = graph;
    this.profile = profile;
    this.mode = mode;
    this.picker = new SkillPicker(graph);
    this.factory = new QuestionFactory();
    this.plan = [];
    this.planIndex = 0;
    this.diagnostic = null;
    this.goal = goal;
    this.skipped = skippedSet(profile, curriculum.id);   // skipped for good
    this.sessionSkips = new Set();                       // skipped for this session only
    this.skippedCount = 0;

    if (mode.type === "focus") {
      // Practicing one chosen skill always works; level, part and review practice leave out skipped skills.
      const focus = mode.skillIds.filter(id => graph.skill(id) && hasPractice(graph.skill(id)) &&
                                               (mode.skillIds.length === 1 || !this.skipped.has(id)));
      const per = focus.length ? Math.max(1, Math.floor(goal / focus.length)) : 0;
      for (let i = 0; i < per; i++) this.plan.push(...focus);
      this.plan.push(...PracticeSession.reviewSkills(mode.reviewCount, new Set([...mode.skillIds, ...this.skipped]), graph, profile, curriculum.id));
      this.goal = this.plan.length;
    } else if (mode.type === "diagnostic") {
      this.diagnostic = new Diagnostic(graph);
      this.goal = curriculum.stages.length * this.diagnostic.questionsPerStage;
    }

    this.session = { id: uuid(), curriculumId: curriculum.id, startedAt: Date.now(), endedAt: null, activeSeconds: 0, attempts: [] };
    this.question = null;
    this.currentSkill = null;
    this.missesBySkill = {};
    this.approach = null;
    this.reason = "advance";
    this.feedback = null;
    this.lessonToShow = null;
    this.isPaused = false;
    this.answered = 0;
    this.correct = 0;
    this.finished = false;
    this.questionStartedAt = 0;
    this.pausedDuringQuestion = 0;
    this.pausedAt = null;
    this.activeSince = null;
  }

  start() { this.activeSince = Date.now(); this.advance(); }

  submit(given) {
    if (!this.question || this.feedback || this.isPaused) return;
    this.record(given, checkAnswer(this.question, given), this.elapsed());
  }
  judge(isCorrect) {
    if (!this.question || this.feedback || this.isPaused || !this.question.tutorJudged) return;
    this.record(isCorrect ? "tutor: correct" : "tutor: incorrect", isCorrect, this.elapsed());
  }
  timeUp() {
    if (!this.question || this.feedback || this.isPaused) return;
    this.record("(time up)", false, Comprehension.questionCapSeconds);
  }
  next() { this.feedback = null; this.lessonToShow = null; this.approach = null; this.advance(); }

  /** Skip the current skill for the rest of this session. Nothing is scored. */
  get canSkip() { return !this.diagnostic && !!this.question && !this.feedback && !this.isPaused && !this.finished; }
  skip() {
    if (!this.canSkip) return;
    const id = this.currentSkill.id;
    this.sessionSkips.add(id);
    this.skippedCount += 1;
    if (this.mode.type === "focus") {
      this.plan = this.plan.slice(0, this.planIndex).concat(this.plan.slice(this.planIndex).filter(x => x !== id));
      this.goal = this.plan.length;
    }
    this.advance();
  }

  pause() {
    if (this.isPaused || this.finished) return;
    this.isPaused = true;
    const now = Date.now();
    this.pausedAt = now;
    if (this.activeSince) this.session.activeSeconds += (now - this.activeSince) / 1000;
    this.activeSince = null;
    this.persist();
  }
  resume() {
    if (!this.isPaused) return;
    this.isPaused = false;
    const now = Date.now();
    if (this.pausedAt) this.pausedDuringQuestion += (now - this.pausedAt) / 1000;
    this.pausedAt = null;
    this.activeSince = now;
  }
  end() {
    if (this.finished) return;
    if (this.activeSince) this.session.activeSeconds += (Date.now() - this.activeSince) / 1000;
    this.activeSince = null;
    this.session.endedAt = Date.now();
    if (this.diagnostic) {
      this.profile.progress[this.curriculum.id] = this.diagnostic.apply(statesOf(this.profile, this.curriculum.id));
    }
    this.finished = true;
    this.question = null;
    this.persist();
  }

  elapsed(now = Date.now()) {
    const paused = this.pausedDuringQuestion + (this.pausedAt ? (now - this.pausedAt) / 1000 : 0);
    return Math.max(0, (now - this.questionStartedAt) / 1000 - paused);
  }
  get activeSeconds() {
    return this.session.activeSeconds + (this.activeSince ? (Date.now() - this.activeSince) / 1000 : 0);
  }

  record(given, isCorrect, seconds) {
    const q = this.question, skill = this.currentSkill;
    if (!q || !skill) return;
    const secs = Math.min(seconds, Comprehension.questionCapSeconds);
    const cid = this.curriculum.id;
    const updated = Comprehension.record(stateOf(this.profile, cid, skill.id), isCorrect, secs, skill.sightPaceSeconds);
    this.profile.progress[cid] = { ...statesOf(this.profile, cid), [skill.id]: updated };
    this.session.attempts.push({ skillId: skill.id, prompt: q.prompt, given, correct: isCorrect, seconds: secs, at: Date.now() });
    if (this.diagnostic) this.diagnostic.record(skill, isCorrect, secs);
    this.answered += 1;
    this.planIndex += 1;
    if (isCorrect) this.correct += 1;
    const pace = skill.sightPaceSeconds ?? Comprehension.defaultSightPace;
    this.feedback = { correct: isCorrect, expected: q.tutorJudged ? null : q.answer, given, why: q.why || null,
                      seconds: secs, sightPace: isCorrect && secs <= pace };
    if (!isCorrect && !this.diagnostic) {
      this.lessonToShow = skill;
      // Each miss on a skill brings the next teaching approach: Show, Do together, Try alone.
      const n = (this.missesBySkill[skill.id] = (this.missesBySkill[skill.id] || 0) + 1);
      this.approach = { index: (n - 1) % 3, ...Approaches[(n - 1) % 3] };
    }
    this.persist();
  }

  advance() {
    const skill = this.nextSkill();
    const tier = !skill ? 1 : this.diagnostic ? 3 : Tiers.current(stateOf(this.profile, this.curriculum.id, skill.id));
    const q = skill ? this.factory.question(skill, tier) : null;
    if (!skill || !q) { this.end(); return; }
    this.currentSkill = skill;
    this.question = q;
    this.questionStartedAt = Date.now();
    this.pausedDuringQuestion = 0;
  }

  nextSkill() {
    if (this.mode.type === "adaptive") {
      if (this.answered >= this.goal) return null;
      const states = statesOf(this.profile, this.curriculum.id);
      const leaveOut = new Set([...this.skipped, ...this.sessionSkips]);
      let pick = this.picker.next(states, Date.now(), leaveOut, this.skipped);
      // If skipping left nothing open, let this session's skips unlock what builds on them too.
      if (!pick.skill && this.sessionSkips.size) pick = this.picker.next(states, Date.now(), leaveOut, leaveOut);
      this.reason = pick.reason;
      return pick.skill;
    }
    if (this.mode.type === "focus") {
      if (this.planIndex >= this.plan.length) return null;
      const tail = Math.min(this.mode.reviewCount, this.plan.length);
      this.reason = this.planIndex < this.plan.length - tail ? "advance" : "review";
      return this.graph.skill(this.plan[this.planIndex]);
    }
    if (!this.diagnostic || this.diagnostic.finished) return null;
    this.reason = "advance";
    return this.diagnostic.nextSkill();
  }

  persist() {
    const snap = { ...this.session, attempts: [...this.session.attempts], activeSeconds: this.activeSeconds };
    const list = this.profile.sessions || (this.profile.sessions = []);
    const i = list.findIndex(s => s.id === snap.id);
    if (i >= 0) list[i] = snap;
    else if (snap.attempts.length || snap.activeSeconds > 0) list.push(snap);
    ProfileStore.save();
  }

  static reviewSkills(count, excluding, graph, profile, cid) {
    if (count <= 0) return [];
    const practiced = graph.ordered.filter(s => !excluding.has(s.id) && hasPractice(s) && stateOf(profile, cid, s.id).attempts > 0);
    const due = practiced.filter(s => SpacedReview.isDue(stateOf(profile, cid, s.id)));
    const weakest = [...practiced].sort((a, b) => stateOf(profile, cid, a.id).comprehension - stateOf(profile, cid, b.id).comprehension);
    const picks = [];
    for (const s of [...due, ...weakest]) {
      if (!picks.includes(s.id)) picks.push(s.id);
      if (picks.length === count) break;
    }
    return picks;
  }
}

if (typeof module !== "undefined") {
  module.exports = { Comprehension, SpacedReview, SkillGraph, SkillPicker, Diagnostic, AnswerChecker,
    makeGenerated, tierParams, QuestionFactory, skippedSet, setSkipped, shortFormsIn, Tiers, PartNames, Approaches, PracticeSession, ProfileStore, hasPractice, newSkillState, ReasonLabel };
}
