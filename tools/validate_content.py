#!/usr/bin/env python3
"""Checks every curriculum file in content/ before it ships in an app.

Run:  python3 tools/validate_content.py

Checks:
  - skill ids are unique; stages and prerequisites exist
  - no prerequisite loops
  - multiple-choice answers are among the choices; auto-graded items have answers
  - every generator named in content exists in TutorCore's Generators.swift
  - day-based plans: days are 1..N with no gaps, and prerequisites come on earlier days
  - every skill is in part 1, 2 or 3 of its level; hand-written questions have a
    difficulty tier (1 Starter, 2 Core, 3 Challenge) and every tier has questions
  - every level and skill has three teaching approaches: show, together, alone
  - every abbreviation (LCM, SD, sin, d/dx, ...) used in lessons, questions or
    generated questions has a plain-English meaning in the curriculum's glossary
Prints a coverage report (skills with practice vs. "coming soon").
Exits with status 1 if anything is wrong.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
GENERATORS_SWIFT = ROOT / "packages/TutorCore/Sources/TutorCore/Questions/Generators.swift"


def generator_keys():
    text = GENERATORS_SWIFT.read_text()
    return set(re.findall(r'^\s*case "([A-Za-z0-9]+)":', text, re.M))


# Capitalized words that are not abbreviations (emphasis, Roman numerals, matrix products).
NOT_ABBREVIATIONS = {"NOT", "II", "III", "IV", "AB", "BA", "AI", "PDP"}
# Lowercase math short forms the checker looks for.
MATH_SHORT_FORMS = ["gcd", "lcm", "mod", "log", "ln", "sin", "cos", "tan", "sec", "csc", "cot", "exp",
                    "opp", "adj", "hyp", "d/dx", "dx", "dy", "dt", "du", "dz", "dA", "lim", "iff", "det",
                    "dim", "div", "max", "min", "sup", "inf", "ker", "im", "Re", "Im", "Var", "Cov",
                    "Gal", "Hom", "e.g.", "i.e.", "etc.", "vs."]
# Short forms that generators put into questions.
GENERATOR_SHORT_FORMS = {"gcd": ["gcd"], "lcm": ["lcm"], "mod": ["mod"], "groupOrder": ["ℤ"],
                         "logBase": ["log"], "derivative": ["f′"], "limit": ["lim"], "det2": ["det"],
                         "integral": ["dx"]}


def term_regex(term):
    return re.compile(r"(?<![A-Za-z-])" + re.escape(term) + r"s?(?![A-Za-z-])")


def texts(skill):
    """Every piece of text a learner or tutor sees for a skill."""
    out = [skill.get("title", ""), skill.get("summary", ""), skill.get("reinforcement") or ""]
    lesson = skill.get("lesson", {})
    out += [lesson.get("explanation", ""), lesson.get("example") or ""] + (lesson.get("tutorSteps") or [])
    out += list((lesson.get("approaches") or {}).values())
    for item in skill.get("practice", {}).get("items") or []:
        out += [item.get("prompt", ""), item.get("answer") or ""] + (item.get("choices") or [])
    return out


APPROACH_KEYS = ("show", "together", "alone")


def check_structure(doc):
    """Parts, difficulty tiers and teaching approaches."""
    errors = []

    def approaches(where, a):
        if not isinstance(a, dict) or any(not (a.get(k) or "").strip() for k in APPROACH_KEYS):
            errors.append(f"{where}: needs three teaching approaches (show, together, alone)")

    for st in doc["stages"]:
        approaches(f"level {st['id']}", st.get("approaches"))
    for s in doc["skills"]:
        sid = s["id"]
        if s.get("part") not in (1, 2, 3):
            errors.append(f"{sid}: part must be 1, 2 or 3")
        approaches(sid, s.get("lesson", {}).get("approaches"))
        items = s.get("practice", {}).get("items") or []
        if items and not s["practice"].get("generator"):
            tiers = [i.get("tier") for i in items]
            if any(t not in (1, 2, 3) for t in tiers):
                errors.append(f"{sid}: every question needs tier 1, 2 or 3")
            for t in (1, 2, 3):
                if t not in tiers:
                    errors.append(f"{sid}: no tier {t} questions")
    return errors


def check_glossary(doc):
    errors = []
    glossary = doc.get("glossary") or []
    terms = set()
    for g in glossary:
        if not g.get("term") or not g.get("meaning"):
            errors.append(f"glossary entry missing term or meaning: {g}")
        terms.add(g.get("term"))
        terms.update((g.get("term") or "").split("-"))  # SOH-CAH-TOA also covers SOH, CAH, TOA
    # Reading and spelling lists (first grade) use real words like "log" and "sin", so lowercase
    # math short forms are only checked in curricula that teach beyond first grade.
    lowercase = MATH_SHORT_FORMS if doc["id"] != "first-grade" else ["e.g.", "i.e.", "etc.", "vs."]
    places = [(s["id"], t) for s in doc["skills"] for t in texts(s)]
    places += [(st["id"], st.get("description") or "") for st in doc["stages"]]
    places += [(st["id"], st.get("title") or "") for st in doc["stages"]]
    places += [(st["id"], t) for st in doc["stages"] for t in (st.get("approaches") or {}).values()]
    missing = {}
    for where, text in places:
        found = set(re.findall(r"(?<![A-Za-z])([A-Z]{2,})(?:s)?(?![A-Za-z])", text))
        found |= {f for f in lowercase if term_regex(f).search(text)}
        for f in found - terms - NOT_ABBREVIATIONS:
            missing.setdefault(f, where)
    for s in doc["skills"]:
        for f in GENERATOR_SHORT_FORMS.get(s.get("practice", {}).get("generator"), []):
            if f not in terms:
                missing.setdefault(f, s["id"] + " (generated questions)")
    for f, where in sorted(missing.items()):
        errors.append(f"'{f}' is used ({where}) but has no meaning in the glossary")
    return errors


def validate(path, keys):
    errors = []
    doc = json.loads(path.read_text())
    stages = {s["id"] for s in doc["stages"]}
    skills = doc["skills"]
    by_id = {}
    for s in skills:
        if s["id"] in by_id:
            errors.append(f"duplicate skill id {s['id']}")
        by_id[s["id"]] = s

    for s in skills:
        sid = s["id"]
        if s["stage"] not in stages:
            errors.append(f"{sid}: unknown stage {s['stage']}")
        for p in s["prerequisites"]:
            if p not in by_id:
                errors.append(f"{sid}: unknown prerequisite {p}")
        for field in ("title", "summary"):
            if not s.get(field):
                errors.append(f"{sid}: missing {field}")
        if not s.get("lesson", {}).get("explanation"):
            errors.append(f"{sid}: missing lesson explanation")
        practice = s.get("practice", {})
        gen = practice.get("generator")
        if gen and gen not in keys:
            errors.append(f"{sid}: generator '{gen}' not in Generators.swift")
        for i, item in enumerate(practice.get("items") or []):
            where = f"{sid} item {i + 1}"
            if not item.get("prompt"):
                errors.append(f"{where}: empty prompt")
            if item.get("mode") == "tutor":
                continue
            if "answer" not in item:
                errors.append(f"{where}: auto-graded item has no answer")
            elif item.get("choices") is not None:
                if item["answer"] not in item["choices"]:
                    errors.append(f"{where}: answer '{item['answer']}' not among choices")
                if len(set(item["choices"])) != len(item["choices"]):
                    errors.append(f"{where}: duplicate choices")

    # Prerequisite loops
    state = {}

    def visit(n, trail):
        if state.get(n) == 1:
            errors.append("prerequisite loop: " + " -> ".join(trail + [n]))
            return
        if state.get(n) == 2:
            return
        state[n] = 1
        for p in by_id.get(n, {}).get("prerequisites", []):
            if p in by_id:
                visit(p, trail + [n])
        state[n] = 2

    for sid in by_id:
        visit(sid, [])

    # Day-based plans
    days = [s.get("day") for s in skills if s.get("day") is not None]
    if days:
        if sorted(days) != list(range(1, len(skills) + 1)):
            errors.append("days must run 1..N with no gaps or repeats")
        for s in skills:
            for p in s["prerequisites"]:
                if p in by_id and by_id[p].get("day", 0) >= s.get("day", 0):
                    errors.append(f"{s['id']} (day {s['day']}) needs {p} (day {by_id[p]['day']}) first")

    errors += check_structure(doc)
    errors += check_glossary(doc)

    with_practice = sum(1 for s in skills if s["practice"].get("generator") or s["practice"].get("items"))
    print(f"{path.relative_to(ROOT)}: {len(doc['stages'])} stages, {len(skills)} skills, "
          f"{with_practice} with practice, {len(skills) - with_practice} coming soon")
    return errors


def main():
    keys = generator_keys()
    files = sorted((ROOT / "content").glob("*/curriculum.json"))
    if not files:
        print("no content files found")
        return 1
    all_errors = []
    for f in files:
        for e in validate(f, keys):
            all_errors.append(f"{f.relative_to(ROOT)}: {e}")
    for e in all_errors:
        print("ERROR", e)
    print("OK" if not all_errors else f"{len(all_errors)} problem(s)")
    return 1 if all_errors else 0


if __name__ == "__main__":
    sys.exit(main())
