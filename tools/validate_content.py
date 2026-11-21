#!/usr/bin/env python3
"""Checks every curriculum file in content/ before it ships in an app.

Run:  python3 tools/validate_content.py

Checks:
  - skill ids are unique; stages and prerequisites exist
  - no prerequisite loops
  - multiple-choice answers are among the choices; auto-graded items have answers
  - every generator named in content exists in TutorCore's Generators.swift
  - day-based plans: days are 1..N with no gaps, and prerequisites come on earlier days
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
