// Screens for the web tutor. One file runs either app:
// APP_CONFIG.kind = "first-grade" (daily lessons) or "math-ladder" (adaptive ladder).
"use strict";

const App = {
  kind: (window.APP_CONFIG && window.APP_CONFIG.kind) || "math-ladder",
  curriculum: null,
  graph: null,
  picker: null,
  profileId: null,
  stack: [],
  session: null,
  typed: "",
  sessionDone: null,
  confirmDelete: null,
  backupOpen: false,
  toastTimer: null,
};

const $root = () => document.getElementById("app");
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pct = x => `${Math.round((x || 0) * 100)}%`;
const mins = secs => `${Math.floor(secs / 60)} min`;

// ---------- Boot ----------
async function boot() {
  ProfileStore.load();
  try {
    App.curriculum = window.CURRICULUM || await (await fetch("curriculum.json")).json();
  } catch (e) {
    $root().innerHTML = `<div class="wrap"><p class="error">The lessons didn't load. Close and reopen the page.</p></div>`;
    return;
  }
  App.graph = new SkillGraph(App.curriculum);
  App.picker = new SkillPicker(App.graph);
  document.title = App.curriculum.title;
  let last = null;
  try { last = localStorage.getItem(`tutor.last.${App.kind}`); } catch (e) {}
  if (last && ProfileStore.get(last)) { App.profileId = last; App.stack = [{ screen: "home" }]; }
  else App.stack = [{ screen: "learners" }];

  document.addEventListener("click", onClick);
  document.addEventListener("keydown", onKey);
  document.addEventListener("input", e => { if (e.target.id === "answer-input") App.typed = e.target.value; });
  document.addEventListener("submit", e => { e.preventDefault(); if (e.target.id === "add-learner") addLearner(); if (e.target.id === "answer-form") sendTyped(); });
  document.addEventListener("change", e => { if (e.target.id === "restore-file") restoreFromFile(e.target); });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden && App.session && !App.session.finished && !App.session.isPaused) { App.session.pause(); render(); }
  });
  setInterval(tick, 250);
  render();
}

// ---------- Navigation ----------
const current = () => App.stack[App.stack.length - 1];
function go(screen, params = {}) { App.stack.push({ screen, ...params }); render(true); }
function back() {
  const cur = current();
  if (cur.screen === "session" && App.session && !App.session.finished) App.session.end();
  if (cur.screen === "session") { App.session = null; App.sessionDone = null; }
  if (App.stack.length > 1) App.stack.pop();
  render(true);
}
function goHome() { App.session = null; App.stack = [{ screen: "home" }]; render(true); }

const profile = () => ProfileStore.get(App.profileId);
const states = () => statesOf(profile(), App.curriculum.id);

// ---------- Rendering ----------
function render(scroll) {
  const cur = current();
  const views = { learners: viewLearners, home: App.kind === "first-grade" ? viewHomeFG : viewHomeML,
    lesson: viewLesson, result: viewResult, session: viewSession, map: viewMap,
    stages: viewStages, stage: viewStage, skill: viewSkill };
  if (cur.screen !== "learners" && !profile()) { App.stack = [{ screen: "learners" }]; return render(true); }
  $root().innerHTML = (views[cur.screen] || viewLearners)(cur);
  if (scroll) window.scrollTo(0, 0);
  const input = document.getElementById("answer-input");
  if (input) { input.value = App.typed; input.focus({ preventScroll: true }); }
}

function bar(title, opts = {}) {
  const left = App.stack.length > 1
    ? `<button class="nav-btn" data-action="back" aria-label="Back">‹ Back</button>`
    : opts.learners ? `<button class="nav-btn" data-action="learners">Learners</button>` : `<span></span>`;
  return `<header class="bar"><div class="bar-in">${left}<h1 class="bar-title">${esc(title)}</h1><span class="bar-right">${opts.right || ""}</span></div></header>`;
}

function dot(level) { return `<span class="dot lv-${level}" aria-hidden="true"></span>`; }
function levelChip(s) {
  const l = Comprehension.level(s);
  const tier = s.attempts > 0 ? ` · ${Tiers.names[Tiers.current(s)]} tier` : "";
  return `<span class="chip lv-${l}">${dot(l)}${Comprehension.levelLabel[l]}${s.attempts > 0 || s.provisional ? ` · ${pct(s.comprehension)}` : ""}${tier}${s.provisional ? " (placement)" : ""}</span>`;
}

// The three teaching approaches, in order: Show, Do together, Try alone.
function approachesList(a, heading) {
  if (!a) return "";
  return `<section class="approaches"><h4>${esc(heading)}</h4><ol>${Approaches.map(x => a[x.key] ? `<li><strong>${x.name}.</strong> <span class="muted small">${x.blurb}</span><br>${esc(a[x.key])}</li>` : "").join("")}</ol></section>`;
}

function stageFullyMastered(stageId) {
  const st = states();
  return App.graph.skillsIn(stageId).every(s => Comprehension.isFullyMastered(st[s.id]));
}

function stageApproaches(stage) {
  if (!stage.approaches || stageFullyMastered(stage.id)) return "";
  return `<details class="card pad stage-approaches"><summary><strong>Three ways to teach this level</strong></summary>
    ${approachesList(stage.approaches, "")}</details>`;
}

function partProgress(stageId) {
  const st = states();
  return `<div class="parts">${App.graph.partsOf(stageId).map(p => {
    const m = p.skills.filter(s => ["mastered", "sight"].includes(Comprehension.level(st[s.id]))).length;
    return `<div class="part"><span class="small"><strong>Part ${p.n}</strong> ${p.name}</span>${meter(m, Math.max(p.skills.length, 1))}<span class="small muted num">${m}/${p.skills.length}</span></div>`;
  }).join("")}</div>`;
}
function meter(value, total) {
  const w = total > 0 ? Math.min(100, Math.max(0, (value / total) * 100)) : 0;
  return `<div class="meter" role="progressbar" aria-valuenow="${value}" aria-valuemax="${total}"><span style="width:${w}%"></span></div>`;
}
function row(label, value) { return `<div class="row"><span>${esc(label)}</span><span class="num">${esc(value)}</span></div>`; }

function skillTexts(skill) {
  const L = skill.lesson || {};
  return [skill.title, skill.summary, L.explanation, L.example, ...(L.tutorSteps || []), skill.reinforcement];
}

// "What the short forms mean": shown wherever an abbreviation appears.
function termsBox(texts) {
  const found = shortFormsIn(App.curriculum, texts);
  if (!found.length) return "";
  return `<dl class="terms"><p class="label">What the short forms mean</p>${found.map(g =>
    `<div><dt>${esc(g.term)}</dt><dd>${esc(g.meaning)}</dd></div>`).join("")}</dl>`;
}

function lessonCard(skill, compact = false, extraTexts = [], approach = null) {
  const L = skill.lesson || {};
  let html = `<article class="lesson ${compact ? "compact" : ""}"><h3>${esc(skill.title)}</h3><p>${esc(L.explanation)}</p>`;
  if (L.example) html += `<p class="example"><span class="label">Example</span>${esc(L.example)}</p>`;
  if (!compact && L.tutorSteps?.length) {
    html += `<h4>Tutor steps</h4><ol>${L.tutorSteps.map(s => `<li>${esc(s)}</li>`).join("")}</ol>`;
  }
  if (!compact && skill.reinforcement) html += `<p class="muted small">Keep it fresh: ${esc(skill.reinforcement)}</p>`;
  const a = L.approaches;
  const extra = [];
  if (compact && approach && a?.[approach.key]) {
    html += `<div class="approach-now"><span class="label">New way to teach it · ${approach.index + 1} of 3</span>
      <p><strong>${approach.name}.</strong> ${esc(a[approach.key])}</p></div>`;
    extra.push(a[approach.key]);
  } else if (!compact && a && !Comprehension.isFullyMastered(stateOf(profile(), App.curriculum.id, skill.id))) {
    html += approachesList(a, "Three ways to teach this");
    extra.push(...Approaches.map(x => a[x.key]));
  }
  const texts = compact ? [skill.title, L.explanation, L.example] : skillTexts(skill);
  return html + termsBox([...texts, ...extra, ...extraTexts]) + `</article>`;
}

function masteredCount() {
  const st = states();
  return App.curriculum.skills.filter(s => ["mastered", "sight"].includes(Comprehension.level(st[s.id]))).length;
}

// ---------- Learners ----------
function viewLearners() {
  const list = ProfileStore.profiles;
  let html = bar(App.curriculum.title);
  html += `<main class="wrap stack">`;
  html += `<section class="intro"><p class="eyebrow">${App.kind === "first-grade" ? "110 daily lessons" : "Grade 1 to doctoral · 33 levels"}</p>
    <h2 class="display">Who's learning today?</h2></section>`;
  if (!ProfileStore.available) html += `<p class="notice">This browser isn't saving progress (private browsing or blocked storage). Open the link in Safari or Chrome normally to keep progress.</p>`;
  html += `<section class="card list">`;
  if (!list.length) html += `<p class="muted pad">No learners yet. Add the first one below.</p>`;
  for (const p of list) {
    const confirming = App.confirmDelete === p.id;
    html += `<div class="learner">
      <button class="learner-main" data-action="pick" data-id="${esc(p.id)}"><span class="avatar">${esc(p.name.slice(0, 1).toUpperCase())}</span>
      <span><strong>${esc(p.name)}</strong><span class="muted small block">${learnerLine(p)}</span></span></button>
      ${confirming
        ? `<span class="confirm"><button class="btn small danger" data-action="delete-yes" data-id="${esc(p.id)}">Delete</button><button class="btn small ghost" data-action="delete-no">Keep</button></span>`
        : `<button class="icon-btn" data-action="delete" data-id="${esc(p.id)}" aria-label="Delete ${esc(p.name)}">✕</button>`}
    </div>`;
  }
  html += `</section>
    <form id="add-learner" class="add-row" autocomplete="off">
      <label for="learner-name" class="sr-only">Learner's name</label>
      <input id="learner-name" class="field" placeholder="Learner's name" maxlength="40">
      <button class="btn primary" type="submit">Add learner</button>
    </form>`;
  html += backupSection();
  html += `<p class="muted small">Progress is saved in this browser on this device. Use “Back up progress” to move it to another phone.</p></main>`;
  return html;
}

function learnerLine(p) {
  if (App.kind === "first-grade") {
    const day = p.currentDay?.[App.curriculum.id] || 1;
    return `Day ${day} of ${App.curriculum.skills.length}`;
  }
  const st = statesOf(p, App.curriculum.id);
  const m = App.curriculum.skills.filter(s => ["mastered", "sight"].includes(Comprehension.level(st[s.id]))).length;
  return `${m} of ${App.curriculum.skills.length} skills mastered`;
}

function backupSection() {
  if (!App.backupOpen) return `<button class="btn ghost wide" data-action="backup-open">Back up or restore progress</button>`;
  const inFrame = window.self !== window.top;
  return `<section class="card pad stack-sm" id="backup">
    <h3>Back up progress</h3>
    <p class="small muted">Copy the backup and paste it into a note, email or text to yourself. To move progress to another phone, open the app there and paste it under Restore.</p>
    <div class="btn-row"><button class="btn primary" data-action="backup-copy">Copy backup</button>
    ${inFrame ? "" : `<button class="btn" data-action="backup-download">Save backup file</button>`}</div>
    <h3>Restore</h3>
    <label for="restore-text" class="small muted">Paste a backup here</label>
    <textarea id="restore-text" class="field" rows="3" spellcheck="false"></textarea>
    <div class="btn-row"><button class="btn" data-action="restore-paste">Restore from pasted text</button>
    <label class="btn ghost file-btn">Choose backup file<input type="file" id="restore-file" accept=".json,application/json,text/plain"></label></div>
    <button class="btn ghost small" data-action="backup-close">Close</button>
  </section>`;
}

// ---------- First Grade home ----------
function fgDay(p = profile()) {
  const total = App.curriculum.skills.length;
  return Math.min(Math.max(p.currentDay?.[App.curriculum.id] || 1, 1), total);
}

function viewHomeFG() {
  const p = profile(), total = App.curriculum.skills.length, day = fgDay(p);
  const skill = App.curriculum.skills.find(s => s.day === day);
  let html = bar(p.name, { learners: true });
  html += `<main class="wrap stack">`;
  if (skill) {
    const s = stateOf(p, App.curriculum.id, skill.id);
    html += `<section class="today">
      <p class="eyebrow">Day ${day} of ${total} · <span class="subj">${esc(skill.subject || "")}</span> · Part ${App.graph.partOfSkill(skill)}: ${PartNames[App.graph.partOfSkill(skill)]}</p>
      <h2 class="display">${esc(skill.title)}</h2>
      <p>${esc(skill.summary)}</p>
      ${levelChip(s)}
      <button class="btn primary big" data-action="lesson" data-id="${esc(skill.id)}">Start today's lesson</button>
    </section>`;
  } else {
    html += `<section class="today"><h2 class="display">All ${total} days complete!</h2></section>`;
  }
  if (skill) {
    const stage = App.graph.stage(skill.stage);
    html += `<section class="card pad stack-sm"><h3>This level: ${esc(stage.title)}</h3>${partProgress(stage.id)}</section>${stageApproaches(stage)}`;
  }
  html += `<section class="card pad stack-sm"><h3>Tutor controls</h3>
    <div class="stepper"><button class="btn" data-action="day" data-delta="-1" ${day <= 1 ? "disabled" : ""} aria-label="Previous day">−</button>
    <span class="num">Day ${day}</span>
    <button class="btn" data-action="day" data-delta="1" ${day >= total ? "disabled" : ""} aria-label="Next day">+</button></div>
    <button class="link-row" data-action="review">Memory review <span class="muted">earlier topics ›</span></button>
    <button class="link-row" data-action="map">Skill map <span class="muted">all ${total} topics ›</span></button>
  </section>`;
  html += `<section class="card pad stack-sm"><h3>Progress</h3>
    ${row("Study time today", mins(studySecondsOn(p)))}
    ${row("Topics mastered", `${masteredCount()} of ${total}`)}
    ${meter(day - 1, total)}
    <p class="small muted">Subtract study time from screen time. Paused time doesn't count.</p>
  </section></main>`;
  return html;
}

// ---------- Math Ladder home ----------
function viewHomeML() {
  const p = profile(), st = states();
  const pick = App.picker.next(st);
  const stage = pick.skill ? App.graph.stage(pick.skill.stage) : null;
  const gaps = App.picker.biggestGaps(st);
  let html = bar(p.name, { learners: true });
  html += `<main class="wrap stack">`;
  html += `<section class="today">
    <p class="eyebrow">Up next · ${ReasonLabel[pick.reason]}</p>
    <h2 class="display">${esc(pick.skill?.title || "Everything available is mastered")}</h2>
    ${stage ? `<p class="muted">${esc(stage.title)}</p>` : ""}
    <button class="btn primary big" data-action="adaptive">Continue practice · 20 questions</button>
  </section>`;
  html += `<section class="card pad stack-sm"><h3>Placement test</h3>
    <p class="small muted">Climbs the ladder a few questions per level and stops where it gets hard. Practice later confirms or corrects the placement.</p>
    <button class="btn" data-action="placement">Take placement test</button></section>`;
  html += `<section class="card pad stack-sm"><h3>Biggest gaps</h3>`;
  if (!gaps.length) html += `<p class="small muted">No gaps found yet. Keep practicing.</p>`;
  for (const g of gaps) html += `<button class="link-row" data-action="skill" data-id="${esc(g.id)}">${esc(g.title)}<span class="num warn">${pct(st[g.id]?.comprehension)}</span></button>`;
  html += `</section>`;
  html += `<section class="card pad stack-sm"><h3>The ladder</h3>
    <button class="link-row" data-action="stages">Browse all levels <span class="muted">›</span></button>
    <button class="link-row" data-action="map">Skill map <span class="muted">›</span></button>
    ${row("Highest level passed", highestStage())}
    ${row("Skills mastered", `${masteredCount()} of ${App.curriculum.skills.length}`)}
  </section>`;
  html += `<section class="card pad stack-sm"><h3>Time</h3>${row("Study time today", mins(studySecondsOn(p)))}
    <p class="small muted">Subtract this from screen time. Paused time doesn't count.</p></section></main>`;
  return html;
}

function highestStage() {
  const st = states();
  let best = null;
  for (const stage of App.graph.stagesSorted) {
    const skills = App.graph.skillsIn(stage.id);
    if (skills.length && skills.every(s => Comprehension.isPassed(st[s.id]))) best = stage;
  }
  return best ? best.title : "Just starting";
}

// ---------- Lesson flow (First Grade) ----------
function viewLesson(cur) {
  const skill = App.graph.skill(cur.id);
  const earlier = (skill.prerequisites || []).map(id => App.graph.skill(id)?.title).filter(Boolean);
  return bar(`Day ${skill.day ?? ""}`) + `<main class="wrap stack">
    <p class="eyebrow">${esc(skill.subject || "")}</p>
    ${lessonCard(skill)}
    ${earlier.length ? `<p class="small muted">Builds on: ${esc(earlier.join(", "))}</p>` : ""}
    <button class="btn primary big" data-action="lesson-practice" data-id="${esc(skill.id)}">Start practice</button>
  </main>`;
}

function viewResult(cur) {
  const skill = App.graph.skill(cur.id);
  const s = stateOf(profile(), App.curriculum.id, skill.id);
  const passed = Comprehension.isPassed(s);
  const last = App.curriculum.skills.length;
  return bar(skill.title) + `<main class="wrap stack center">
    <h2 class="display">${esc(skill.title)}</h2>
    ${levelChip(s)}
    ${s.averageSeconds != null ? `<p class="muted">Average ${s.averageSeconds.toFixed(1)} s per question</p>` : ""}
    <p>${passed ? "Ready for the next day." : "Not passed yet. Practice again tomorrow, or move on if you're sure."}</p>
    <div class="stack-sm">
    ${skill.day && skill.day < last ? `<button class="btn primary big" data-action="move-on" data-day="${skill.day + 1}">${passed ? `Go to Day ${skill.day + 1}` : "Move on anyway"}</button>` : ""}
    <button class="btn" data-action="lesson-practice" data-id="${esc(skill.id)}">Practice again</button>
    <button class="btn ghost" data-action="home">Back to home</button></div>
  </main>`;
}

// ---------- Ladder browsing (Math Ladder) ----------
function viewStages() {
  const st = states();
  const levels = [];
  for (const s of App.graph.stagesSorted) { const l = s.level || "Other"; if (!levels.includes(l)) levels.push(l); }
  let html = bar("The ladder") + `<main class="wrap stack">`;
  for (const level of levels) {
    html += `<section><h3 class="section-h">${esc(level)}</h3><div class="card list">`;
    for (const stage of App.graph.stagesSorted.filter(s => (s.level || "Other") === level)) {
      const skills = App.graph.skillsIn(stage.id);
      const passed = skills.filter(s => Comprehension.isPassed(st[s.id])).length;
      html += `<button class="stage-row" data-action="stage" data-id="${esc(stage.id)}">
        <span class="stage-top"><strong>${esc(stage.title)}</strong><span class="num muted">${passed}/${skills.length}</span></span>
        ${stage.description ? `<span class="small muted">${esc(stage.description)}</span>` : ""}
        ${partProgress(stage.id)}</button>`;
    }
    html += `</div></section>`;
  }
  return html + `</main>`;
}

function viewStage(cur) {
  const stage = App.graph.stage(cur.id), st = states();
  let html = bar(stage.title) + `<main class="wrap stack">
    ${stage.description ? `<p class="muted">${esc(stage.description)}</p>` : ""}
    <button class="btn primary big" data-action="stage-practice" data-id="${esc(stage.id)}">Practice this level</button>
    ${stageApproaches(stage)}`;
  for (const part of App.graph.partsOf(stage.id)) {
    if (!part.skills.length) continue;
    const m = part.skills.filter(s => ["mastered", "sight"].includes(Comprehension.level(st[s.id]))).length;
    html += `<section><h3 class="section-h"><span>Part ${part.n} · ${part.name}</span><span class="num small">${m}/${part.skills.length} mastered</span></h3><div class="card list">`;
    for (const s of part.skills) {
      const x = st[s.id], l = Comprehension.level(x);
      const tier = x?.attempts ? ` · ${Tiers.names[Tiers.current(x)]}` : "";
      html += `<button class="skill-row" data-action="skill" data-id="${esc(s.id)}">${dot(l)}<span class="grow">${esc(s.title)}</span><span class="small muted">${Comprehension.levelLabel[l]}${tier}</span></button>`;
    }
    html += `</div><button class="btn ghost small" data-action="stage-practice" data-id="${esc(stage.id)}" data-part="${part.n}">Practice Part ${part.n}</button></section>`;
  }
  return html + `</main>`;
}

function viewSkill(cur) {
  const skill = App.graph.skill(cur.id), s = stateOf(profile(), App.curriculum.id, skill.id);
  const prereqs = (skill.prerequisites || []).map(id => App.graph.skill(id)).filter(Boolean);
  const stage = App.graph.stage(skill.stage), part = App.graph.partOfSkill(skill);
  let html = bar(skill.title) + `<main class="wrap stack">
    <p class="eyebrow">${esc(stage.title)} · Part ${part}: ${PartNames[part]}</p>${lessonCard(skill)}
    <div>${levelChip(s)}${s.attempts ? ` <span class="small muted">${s.attempts} answered</span>` : ""}</div>`;
  if (prereqs.length) {
    html += `<section class="card pad stack-sm"><h3>Builds on</h3>${prereqs.map(p => `<button class="link-row" data-action="skill" data-id="${esc(p.id)}">${dot(Comprehension.level(states()[p.id]))}<span class="grow">${esc(p.title)}</span><span class="muted">›</span></button>`).join("")}</section>`;
  }
  if (hasPractice(skill)) html += `<button class="btn primary big" data-action="skill-practice" data-id="${esc(skill.id)}">Practice this skill</button>`;
  else html += `<p class="muted small">Practice for this skill is coming soon.</p>`;
  return html + `</main>`;
}

// ---------- Skill map ----------
function viewMap() {
  const st = states();
  let sections;
  if (App.kind === "first-grade") {
    const subjects = [...new Set(App.curriculum.skills.map(s => s.subject).filter(Boolean))].sort();
    sections = subjects.map(sub => ({ title: sub, skills: App.curriculum.skills.filter(s => s.subject === sub).sort((a, b) => (a.day ?? 0) - (b.day ?? 0)) }));
  } else {
    sections = App.graph.stagesSorted.map(stage => ({ title: stage.title, skills: App.graph.skillsIn(stage.id) }));
  }
  let html = bar("Skill map") + `<main class="wrap stack">
    <div class="legend">${["new", "learning", "passing", "mastered", "sight"].map(l => `<span>${dot(l)}${Comprehension.levelLabel[l]}</span>`).join("")}</div>`;
  for (const sec of sections) {
    const m = sec.skills.filter(s => ["mastered", "sight"].includes(Comprehension.level(st[s.id]))).length;
    html += `<section><h3 class="section-h"><span>${esc(sec.title)}</span><span class="num muted small">${m}/${sec.skills.length} mastered</span></h3><div class="card list">`;
    for (const s of sec.skills) {
      const x = st[s.id] || newSkillState(), l = Comprehension.level(x);
      const right = !hasPractice(s) ? `<span class="small muted">coming soon</span>` : (x.attempts > 0 || x.provisional) ? `<span class="num">${pct(x.comprehension)}</span>` : "";
      html += `<button class="skill-row" data-action="skill" data-id="${esc(s.id)}">${dot(l)}<span class="grow">${s.day ? `<span class="muted small num">Day ${s.day}</span> ` : ""}${esc(s.title)}</span>${right}</button>`;
    }
    html += `</div></section>`;
  }
  return html + `</main>`;
}

// ---------- Practice session ----------
function startSession(mode, goal, title, onDone) {
  App.session = new PracticeSession(App.curriculum, App.graph, profile(), mode, goal);
  App.sessionDone = onDone || null;
  App.typed = "";
  App.session.start();
  go("session", { title });
}

const keypadOK = q => !q.choices && !q.tutorJudged && q.answer != null && /^[-−\d\/:.]+$/.test(q.answer);

function viewSession(cur) {
  const s = App.session;
  if (!s) return bar(cur.title) + `<main class="wrap"><p class="muted">Session ended.</p></main>`;
  const right = s.finished ? "" : `<button class="nav-btn" data-action="${s.isPaused ? "resume" : "pause"}">${s.isPaused ? "Resume" : "Pause"}</button>`;
  let html = bar(cur.title, { right });
  html += `<main class="wrap practice">`;
  if (!s.finished) {
    html += `<div class="practice-head"><div><strong>${esc(s.currentSkill?.title || "")}</strong>
      <span class="small muted block">${ReasonLabel[s.reason]}${s.question?.tier && !s.diagnostic ? ` · ${Tiers.names[s.question.tier]} tier` : ""}</span></div>
      <span class="num count">${Math.min(s.answered + (s.feedback ? 0 : 1), Math.max(s.goal, 1))}/${s.goal}</span>
      <button class="btn small ghost" data-action="end">End</button></div>`;
  }
  if (s.finished) html += summaryView(s);
  else if (s.isPaused) html += `<section class="center stack"><h2 class="display">Paused</h2><p class="muted">The clock is stopped. Progress so far is saved.</p><button class="btn primary big" data-action="resume">Resume</button></section>`;
  else if (s.feedback) html += feedbackView(s);
  else if (s.question) html += questionView(s.question);
  return html + `</main>`;
}

function questionView(q) {
  const left = Math.max(0, Comprehension.questionCapSeconds - App.session.elapsed());
  let html = `<div class="timer" aria-hidden="true"><span id="timer-fill" class="${left > 15 ? "" : "late"}" style="width:${(left / 60) * 100}%"></span></div>
    <p class="prompt">${esc(q.prompt)}</p>
    ${termsBox([q.prompt, ...(q.choices || [])])}`;
  if (q.choices) {
    html += `<div class="choices">${q.choices.map(c => `<button class="choice" data-action="choose" data-value="${esc(c)}">${esc(c)}</button>`).join("")}</div>`;
  } else if (q.tutorJudged) {
    html += `<p class="small muted center">Tutor: mark the answer</p><div class="btn-row center-row">
      <button class="btn big warn-btn" data-action="judge" data-ok="0">Not yet</button>
      <button class="btn big ok-btn" data-action="judge" data-ok="1">Correct</button></div>`;
  } else if (keypadOK(q)) {
    const keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", "-", "0", "⌫"];
    const extra = [];
    if (/\//.test(q.answer)) extra.push("/");
    if (/:/.test(q.answer)) extra.push(":");
    if (/\./.test(q.answer)) extra.push(".");
    html += `<div class="answer-box num" aria-live="polite">${esc(App.typed) || `<span class="muted">?</span>`}</div>
      <div class="keypad">${keys.map(k => `<button class="key" data-action="key" data-key="${k}">${k}</button>`).join("")}
      ${extra.map(k => `<button class="key alt" data-action="key" data-key="${k}">${k}</button>`).join("")}</div>
      <button class="btn primary big wide" data-action="check" ${App.typed ? "" : "disabled"}>Check</button>`;
  } else {
    html += `<form id="answer-form" class="add-row" autocomplete="off">
      <label for="answer-input" class="sr-only">Answer</label>
      <input id="answer-input" class="field big-field" placeholder="Answer" autocapitalize="off" autocorrect="off" spellcheck="false">
      <button class="btn primary" type="submit">Check</button></form>`;
  }
  return html;
}

function feedbackView(s) {
  const fb = s.feedback;
  return `<section class="feedback stack ${fb.correct ? "good" : "miss"}">
    <h2 class="display">${fb.correct ? (fb.sightPace ? "Right, at sight pace!" : "Right!") : "Not quite"}</h2>
    ${!fb.correct && fb.expected ? `<p class="answer-reveal">${fb.given && fb.given !== "(time up)" ? `You answered <strong class="given">${esc(fb.given)}</strong>. ` : fb.given === "(time up)" ? "Time ran out. " : ""}The answer is <strong>${esc(fb.expected)}</strong>.</p>` : ""}
    <p class="muted num">${fb.seconds.toFixed(1)} seconds</p>
    ${fb.why ? `<div class="why"><span class="label">${fb.correct ? "Why it's right" : "Why"}</span><p>${esc(fb.why)}</p></div>` : ""}
    ${s.lessonToShow ? lessonCard(s.lessonToShow, true, [s.question?.prompt, fb.expected, fb.why], s.approach)
                     : termsBox([s.question?.prompt, fb.expected, fb.why])}
    <button class="btn primary big" data-action="next" id="next-btn">${s.lessonToShow ? "Got it, try another" : "Next"}</button>
  </section>`;
}

function summaryView(s) {
  const secs = Math.round(s.activeSeconds);
  let placed = "";
  if (s.diagnostic) {
    const last = s.diagnostic.passedStages[s.diagnostic.passedStages.length - 1];
    placed = `<p>Placed through: <strong>${esc(last ? App.graph.stage(last).title : "the start")}</strong></p>`;
  }
  return `<section class="center stack"><h2 class="display">Session done</h2>
    <p class="big-num num">${s.correct} of ${s.answered} right</p>
    <p class="muted">Study time: ${Math.floor(secs / 60)} min ${secs % 60} s</p>${placed}
    <button class="btn primary big" data-action="session-done">Done</button></section>`;
}

function sendTyped() {
  const a = App.typed.trim();
  if (!a || !App.session) return;
  App.session.submit(a);
  App.typed = "";
  render();
}

function tick() {
  const s = App.session;
  if (!s || current().screen !== "session" || s.finished || s.isPaused || s.feedback || !s.question) return;
  const left = Math.max(0, Comprehension.questionCapSeconds - s.elapsed());
  const fill = document.getElementById("timer-fill");
  if (fill) { fill.style.width = `${(left / 60) * 100}%`; fill.classList.toggle("late", left <= 15); }
  if (left <= 0) { s.timeUp(); render(); }
}

// ---------- Events ----------
function onClick(e) {
  const el = e.target.closest("[data-action]");
  if (!el) return;
  const a = el.dataset.action, id = el.dataset.id;
  const s = App.session;
  switch (a) {
    case "back": return back();
    case "home": return goHome();
    case "learners": App.confirmDelete = null; App.stack = [{ screen: "learners" }]; return render(true);
    case "pick":
      App.profileId = id;
      try { localStorage.setItem(`tutor.last.${App.kind}`, id); } catch (err) {}
      return goHome();
    case "delete": App.confirmDelete = id; return render();
    case "delete-no": App.confirmDelete = null; return render();
    case "delete-yes": ProfileStore.remove(id); App.confirmDelete = null; return render();
    case "backup-open": App.backupOpen = true; render(); return document.getElementById("backup")?.scrollIntoView({ block: "start" });
    case "backup-close": App.backupOpen = false; return render();
    case "backup-copy": return copyBackup();
    case "backup-download": return downloadBackup();
    case "restore-paste": return restoreFrom(document.getElementById("restore-text").value);

    case "day": {
      const p = profile(); const total = App.curriculum.skills.length;
      p.currentDay = p.currentDay || {};
      p.currentDay[App.curriculum.id] = Math.min(total, Math.max(1, fgDay(p) + Number(el.dataset.delta)));
      ProfileStore.save(); return render();
    }
    case "lesson": return go("lesson", { id });
    case "lesson-practice": {
      const skill = App.graph.skill(id);
      // Replace the lesson/result screen so Back returns home.
      if (["lesson", "result"].includes(current().screen)) App.stack.pop();
      App.stack.push({ screen: "lesson", id });
      return startSession({ type: "focus", skillIds: [id], reviewCount: 4 }, 8, `Day ${skill.day ?? ""}`, () => {
        App.session = null; App.stack.pop(); App.stack.pop(); App.stack.push({ screen: "result", id }); render(true);
      });
    }
    case "move-on": {
      const p = profile(); p.currentDay = p.currentDay || {};
      p.currentDay[App.curriculum.id] = Number(el.dataset.day); ProfileStore.save(); return goHome();
    }
    case "review": return startSession({ type: "focus", skillIds: [], reviewCount: 10 }, 20, "Memory review");
    case "map": return go("map");
    case "adaptive": return startSession({ type: "adaptive" }, 20, "Practice");
    case "placement": return startSession({ type: "diagnostic" }, 20, "Placement test");
    case "stages": return go("stages");
    case "stage": return go("stage", { id });
    case "skill": return go("skill", { id });
    case "stage-practice": {
      const part = Number(el.dataset.part) || 0;
      const skills = part ? App.graph.partsOf(id)[part - 1].skills : App.graph.skillsIn(id);
      const ids = skills.map(x => x.id);
      const title = App.graph.stage(id).title + (part ? ` · Part ${part}` : "");
      return startSession({ type: "focus", skillIds: ids, reviewCount: 3 }, Math.max(ids.length * 2, 12), title);
    }
    case "skill-practice": return startSession({ type: "focus", skillIds: [id], reviewCount: 2 }, 10, App.graph.skill(id).title);

    case "pause": s?.pause(); return render();
    case "resume": s?.resume(); return render();
    case "end": s?.end(); return render();
    case "choose": s?.submit(el.dataset.value); return render();
    case "judge": s?.judge(el.dataset.ok === "1"); return render();
    case "key": return pressKey(el.dataset.key);
    case "check": return sendTyped();
    case "next": App.typed = ""; s?.next(); return render();
    case "session-done": {
      const done = App.sessionDone; App.sessionDone = null;
      if (done) return done();
      App.session = null; App.stack.pop(); return render(true);
    }
  }
}

function pressKey(k) {
  if (k === "⌫" || k === "Backspace") App.typed = App.typed.slice(0, -1);
  else if (App.typed.length < 12) App.typed += k;
  render();
}

function onKey(e) {
  const s = App.session;
  if (!s || current().screen !== "session" || s.finished || s.isPaused) return;
  if (s.feedback) {
    if (e.key === "Enter") { e.preventDefault(); App.typed = ""; s.next(); render(); }
    return;
  }
  const q = s.question;
  if (!q || !keypadOK(q) || e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") return;
  if (/^[0-9\-\/:.]$/.test(e.key)) { e.preventDefault(); pressKey(e.key); }
  else if (e.key === "Backspace") { e.preventDefault(); pressKey("⌫"); }
  else if (e.key === "Enter") { e.preventDefault(); sendTyped(); }
}

function addLearner() {
  const input = document.getElementById("learner-name");
  const name = input.value.trim();
  if (!name) { input.focus(); return; }
  ProfileStore.add(name);
  render();
}

// ---------- Backup ----------
function toast(msg) {
  let t = document.getElementById("toast");
  if (!t) { t = document.createElement("div"); t.id = "toast"; t.setAttribute("role", "status"); document.body.appendChild(t); }
  t.textContent = msg; t.classList.add("show");
  clearTimeout(App.toastTimer);
  App.toastTimer = setTimeout(() => t.classList.remove("show"), 2600);
}

function copyBackup() {
  const text = ProfileStore.exportText();
  const fallback = () => {
    const ta = document.getElementById("restore-text");
    ta.value = text; ta.focus(); ta.select();
    toast("Backup selected below. Tap Copy.");
  };
  try {
    navigator.clipboard.writeText(text).then(() => toast("Backup copied. Paste it somewhere safe."), fallback);
  } catch (e) { fallback(); }
}

function downloadBackup() {
  const blob = new Blob([ProfileStore.exportText()], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = `tutor-progress-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

function restoreFrom(text) {
  if (!text || !text.trim()) { toast("Paste a backup first."); return; }
  try {
    const n = ProfileStore.importText(text.trim());
    App.backupOpen = false;
    render();
    toast(`Restored ${n} learner${n === 1 ? "" : "s"}.`);
  } catch (e) {
    toast("That isn't a progress backup. Copy the whole backup and try again.");
  }
}

function restoreFromFile(input) {
  const f = input.files && input.files[0];
  if (!f) return;
  const r = new FileReader();
  r.onload = () => restoreFrom(String(r.result));
  r.readAsText(f);
}

boot();
