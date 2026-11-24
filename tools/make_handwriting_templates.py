#!/usr/bin/env python3
"""Builds content/handwriting/templates.json: model shapes for a-z, A-Z and 0-9.

Shapes follow the ball-and-stick manuscript print taught in US first grade, drawn
on handwriting-paper guide lines:  y = 2 top line, y = 1 dashed middle line,
y = 0 baseline, y = -1 bottom of tails. x runs left to right, about 0..1.

Each character is a list of strokes; each stroke is a list of [x, y] points.
Some characters have more than one common form (for example 4 open or closed).
The apps compare a child's strokes with these shapes (the $P point-cloud method),
so stroke order and direction don't matter.

    python3 tools/make_handwriting_templates.py
"""
import json
import math
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "content" / "handwriting" / "templates.json"


def arc(cx, cy, rx, ry, a0, a1, n=None):
    """Points along an ellipse from angle a0 to a1 (degrees, 0 = right, 90 = up)."""
    n = n or max(6, int(abs(a1 - a0) / 12))
    return [[round(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)), 3),
             round(cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n)), 3)] for i in range(n + 1)]


def line(*pts):
    return [list(p) for p in pts]


def join(*parts):
    """One stroke made of several pieces drawn without lifting the pencil."""
    out = []
    for part in parts:
        out += part if not out or out[-1] != part[0] else part[1:]
    return out


def dot(x, y):
    return [[x, y], [x + 0.02, y - 0.02]]


G = {}
# ---- lowercase (x-height letters sit between y=0 and y=1) ----
G["a"] = [[arc(0.45, 0.5, 0.42, 0.5, 60, 420), line((0.88, 1), (0.88, 0))]]
G["b"] = [[line((0.1, 2), (0.1, 0)), arc(0.5, 0.5, 0.4, 0.5, 180, -180)]]
G["c"] = [[arc(0.5, 0.5, 0.45, 0.5, 45, 315)]]
G["d"] = [[arc(0.45, 0.5, 0.42, 0.5, 60, 420), line((0.88, 2), (0.88, 0))]]
G["e"] = [[join(line((0.05, 0.5), (0.95, 0.5)), arc(0.5, 0.5, 0.45, 0.5, 0, 320))]]
G["f"] = [[join(arc(0.65, 1.6, 0.25, 0.3, 30, 180), line((0.4, 1.6), (0.4, 0))), line((0.1, 1), (0.75, 1))]]
G["g"] = [[arc(0.45, 0.5, 0.42, 0.5, 60, 420), join(line((0.88, 1), (0.88, -0.6)), arc(0.5, -0.6, 0.38, 0.4, 0, -165))]]
G["h"] = [[line((0.1, 2), (0.1, 0)), join(arc(0.5, 0.55, 0.4, 0.45, 180, 0), line((0.9, 0.55), (0.9, 0)))]]
G["i"] = [[line((0.5, 1), (0.5, 0)), dot(0.5, 1.5)]]
G["j"] = [[join(line((0.6, 1), (0.6, -0.6)), arc(0.3, -0.6, 0.3, 0.38, 0, -180)), dot(0.6, 1.5)]]
G["k"] = [[line((0.1, 2), (0.1, 0)), line((0.8, 1), (0.1, 0.4)), line((0.35, 0.6), (0.85, 0))]]
G["l"] = [[line((0.5, 2), (0.5, 0))]]
G["m"] = [[line((0.05, 1), (0.05, 0)),
           join(arc(0.275, 0.55, 0.225, 0.45, 180, 0), line((0.5, 0.55), (0.5, 0))),
           join(arc(0.725, 0.55, 0.225, 0.45, 180, 0), line((0.95, 0.55), (0.95, 0)))]]
G["n"] = [[line((0.1, 1), (0.1, 0)), join(arc(0.5, 0.55, 0.4, 0.45, 180, 0), line((0.9, 0.55), (0.9, 0)))]]
G["o"] = [[arc(0.5, 0.5, 0.45, 0.5, 90, 450)]]
G["p"] = [[line((0.1, 1), (0.1, -1)), arc(0.5, 0.5, 0.4, 0.5, 180, -180)]]
G["q"] = [[arc(0.45, 0.5, 0.42, 0.5, 60, 420), line((0.88, 1), (0.88, -1))]]
G["r"] = [[line((0.15, 1), (0.15, 0)), arc(0.5, 0.6, 0.35, 0.4, 180, 30)]]
G["s"] = [[join(arc(0.5, 0.75, 0.38, 0.25, 30, 270), arc(0.5, 0.25, 0.4, 0.25, 90, -150))]]
G["t"] = [[line((0.5, 1.8), (0.5, 0)), line((0.15, 1), (0.85, 1))]]
G["u"] = [[join(line((0.1, 1), (0.1, 0.45)), arc(0.5, 0.45, 0.4, 0.45, 180, 360), line((0.9, 0.45), (0.9, 1))),
           line((0.9, 1), (0.9, 0))]]
G["v"] = [[line((0.05, 1), (0.5, 0), (0.95, 1))]]
G["w"] = [[line((0, 1), (0.25, 0), (0.5, 0.8), (0.75, 0), (1, 1))]]
G["x"] = [[line((0.1, 1), (0.9, 0)), line((0.9, 1), (0.1, 0))]]
G["y"] = [[line((0.1, 1), (0.5, 0)), line((0.9, 1), (0.3, -1))]]
G["z"] = [[line((0.1, 1), (0.9, 1), (0.1, 0), (0.9, 0))]]

# ---- capitals (y=0 to y=2) ----
G["A"] = [[line((0.05, 0), (0.5, 2), (0.95, 0)), line((0.25, 0.8), (0.75, 0.8))]]
G["B"] = [[line((0.1, 2), (0.1, 0)),
           join(line((0.1, 2), (0.5, 2)), arc(0.5, 1.5, 0.35, 0.5, 90, -90), line((0.5, 1), (0.1, 1))),
           join(line((0.1, 1), (0.5, 1)), arc(0.5, 0.5, 0.42, 0.5, 90, -90), line((0.5, 0), (0.1, 0)))]]
G["C"] = [[arc(0.55, 1, 0.5, 1, 45, 315)]]
G["D"] = [[line((0.1, 2), (0.1, 0)), join(line((0.1, 2), (0.4, 2)), arc(0.4, 1, 0.5, 1, 90, -90), line((0.4, 0), (0.1, 0)))]]
G["E"] = [[line((0.1, 2), (0.1, 0)), line((0.1, 2), (0.9, 2)), line((0.1, 1), (0.7, 1)), line((0.1, 0), (0.9, 0))]]
G["F"] = [[line((0.1, 2), (0.1, 0)), line((0.1, 2), (0.9, 2)), line((0.1, 1), (0.7, 1))]]
G["G"] = [[arc(0.55, 1, 0.5, 1, 50, 360), line((1.05, 1), (0.6, 1))]]
G["H"] = [[line((0.1, 2), (0.1, 0)), line((0.9, 2), (0.9, 0)), line((0.1, 1), (0.9, 1))]]
G["I"] = [[line((0.5, 2), (0.5, 0)), line((0.2, 2), (0.8, 2)), line((0.2, 0), (0.8, 0))]]
G["J"] = [[join(line((0.7, 2), (0.7, 0.5)), arc(0.4, 0.5, 0.3, 0.5, 0, -180))]]
G["K"] = [[line((0.1, 2), (0.1, 0)), line((0.9, 2), (0.1, 0.8)), line((0.4, 1.1), (0.9, 0))]]
G["L"] = [[line((0.1, 2), (0.1, 0), (0.9, 0))]]
G["M"] = [[line((0.05, 0), (0.05, 2), (0.5, 0.8), (0.95, 2), (0.95, 0))]]
G["N"] = [[line((0.1, 0), (0.1, 2), (0.9, 0), (0.9, 2))]]
G["O"] = [[arc(0.5, 1, 0.45, 1, 90, 450)]]
G["P"] = [[line((0.1, 2), (0.1, 0)), join(line((0.1, 2), (0.5, 2)), arc(0.5, 1.5, 0.4, 0.5, 90, -90), line((0.5, 1), (0.1, 1)))]]
G["Q"] = [[arc(0.5, 1, 0.45, 1, 90, 450), line((0.6, 0.4), (1, -0.05))]]
G["R"] = [[line((0.1, 2), (0.1, 0)), join(line((0.1, 2), (0.5, 2)), arc(0.5, 1.5, 0.4, 0.5, 90, -90), line((0.5, 1), (0.1, 1))),
           line((0.4, 1), (0.9, 0))]]
G["S"] = [[join(arc(0.5, 1.5, 0.4, 0.5, 30, 270), arc(0.5, 0.5, 0.45, 0.5, 90, -150))]]
G["T"] = [[line((0.5, 2), (0.5, 0)), line((0.05, 2), (0.95, 2))]]
G["U"] = [[join(line((0.1, 2), (0.1, 0.6)), arc(0.5, 0.6, 0.4, 0.6, 180, 360), line((0.9, 0.6), (0.9, 2)))]]
G["V"] = [[line((0.05, 2), (0.5, 0), (0.95, 2))]]
G["W"] = [[line((0, 2), (0.25, 0), (0.5, 1.4), (0.75, 0), (1, 2))]]
G["X"] = [[line((0.1, 2), (0.9, 0)), line((0.9, 2), (0.1, 0))]]
G["Y"] = [[line((0.1, 2), (0.5, 1), (0.9, 2)), line((0.5, 1), (0.5, 0))]]
G["Z"] = [[line((0.1, 2), (0.9, 2), (0.1, 0), (0.9, 0))]]

# ---- digits (y=0 to y=2) ----
G["0"] = [[arc(0.5, 1, 0.4, 1, 90, 450)]]
G["1"] = [[line((0.5, 2), (0.5, 0))], [line((0.25, 1.6), (0.5, 2), (0.5, 0))]]
G["2"] = [[join(arc(0.5, 1.5, 0.4, 0.5, 160, -30), line((0.82, 1.2), (0.1, 0), (0.9, 0)))]]
G["3"] = [[join(arc(0.5, 1.5, 0.38, 0.5, 150, -90), arc(0.5, 0.5, 0.45, 0.5, 90, -150))]]
G["4"] = [[line((0.7, 0), (0.7, 2), (0.05, 0.6), (0.95, 0.6))],
          [line((0.15, 2), (0.15, 0.9), (0.95, 0.9)), line((0.7, 2), (0.7, 0))]]
G["5"] = [[line((0.85, 2), (0.2, 2)), join(line((0.2, 2), (0.15, 1.2)), arc(0.5, 0.6, 0.45, 0.6, 140, -150))]]
G["6"] = [[join(arc(0.65, 1.0, 0.55, 1.0, 70, 200), arc(0.5, 0.55, 0.4, 0.55, 200, 560))]]
G["7"] = [[line((0.1, 2), (0.9, 2), (0.35, 0))]]
G["8"] = [[arc(0.5, 1.5, 0.35, 0.5, 270, 630), arc(0.5, 0.5, 0.42, 0.5, 90, 450)]]
G["9"] = [[arc(0.5, 1.45, 0.4, 0.55, 0, 360), line((0.9, 1.45), (0.82, 0))]]


def main():
    chars = {}
    for ch, variants in G.items():
        if isinstance(variants[0][0][0], (int, float)):  # a single form given as a list of strokes
            variants = [variants]
        chars[ch] = variants
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = {
        "about": "Model handwriting shapes. Guide lines: y=2 top, y=1 middle (dashed), y=0 baseline, y=-1 tails. "
                 "Built by tools/make_handwriting_templates.py; edit that file, not this one.",
        "chars": chars,
    }
    OUT.write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    print(f"wrote {OUT.relative_to(OUT.parent.parent.parent)}: {len(chars)} characters, "
          f"{sum(len(v) for v in chars.values())} shapes")


if __name__ == "__main__":
    main()
