#!/usr/bin/env python3
"""Build the web versions of the tutor apps.

Each app becomes ONE self-contained .html file (lessons, engine and screens
inside), so it can be texted, emailed, hosted anywhere, or opened offline.

    python3 tools/build_web.py                 # writes docs/*.html (served by GitHub Pages)
    python3 tools/build_web.py --artifact DIR  # also writes claude.ai artifact pages to DIR

Run tools/validate_content.py first; this script only packages what is there.
"""
import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "web" / "src"
DIST = ROOT / "docs"  # GitHub Pages serves this folder

APPS = [
    # (kind, content folder, output file, short name for the home screen icon)
    ("first-grade", "first-grade", "first-grade-tutor.html", "1st Grade"),
    ("math-ladder", "math-ladder", "math-ladder.html", "Math Ladder"),
]

FONTS = ('<link rel="preconnect" href="https://fonts.googleapis.com">'
         '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lexend:wght@400;500;600&display=swap">')


def script_safe(text: str) -> str:
    """Keep inline <script> blocks from being closed early by their content."""
    return text.replace("</", "<\\/")


def page_body(kind: str, curriculum_json: str | None) -> str:
    engine = (SRC / "engine.js").read_text()
    handwriting = (SRC / "handwriting.js").read_text()
    templates = (ROOT / "content" / "handwriting" / "templates.json").read_text().strip()
    app = (SRC / "app.js").read_text()
    parts = ['<div id="app"><div style="padding:24px;font-family:system-ui,sans-serif;line-height:1.5">'
             '<p>Loading…</p><p id="load-help" hidden>The app didn\'t start. Open this link in Safari, Chrome or Edge '
             '(not inside a text message or email preview), or update the device\'s software.</p></div></div>',
             # If the app hasn't started after a few seconds (very old browser, or a preview that blocks scripts), say how to fix it.
             '<script>setTimeout(function(){var h=document.getElementById("load-help");if(h)h.hidden=false;},4000);</script>',
             f'<script>window.APP_CONFIG = {json.dumps({"kind": kind})};</script>']
    if curriculum_json is not None:
        parts.append(f'<script>window.CURRICULUM = {script_safe(curriculum_json)};</script>')
    parts.append(f"<script>window.HANDWRITING = {script_safe(templates)};</script>")
    parts.append(f"<script>\n{engine}\n</script>")
    parts.append(f"<script>\n{handwriting}\n</script>")
    parts.append(f"<script>\n{app}\n</script>")
    return "\n".join(parts)


def head(title: str, short: str) -> str:
    css = (SRC / "style.css").read_text()
    return "\n".join([
        f"<title>{title}</title>",
        '<meta name="claude:viewport-fit-sides" content="cover">',
        '<meta name="apple-mobile-web-app-capable" content="yes">',
        '<meta name="mobile-web-app-capable" content="yes">',
        f'<meta name="apple-mobile-web-app-title" content="{short}">',
        '<meta name="theme-color" content="#1f4fa3">',
        FONTS,
        f"<style>\n{css}\n</style>",
    ])


def standalone(kind: str, curriculum: dict, short: str) -> str:
    data = json.dumps(curriculum, ensure_ascii=False, separators=(",", ":"))
    return "\n".join([
        "<!doctype html>",
        '<html lang="en">',
        "<head>",
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
        head(curriculum["title"], short),
        "</head>",
        "<body>",
        page_body(kind, data),
        "</body>",
        "</html>",
        "",
    ])


def index_page() -> str:
    links = "\n".join(
        f'<a class="card pad" href="{out}" style="display:block;color:inherit;text-decoration:none">'
        f'<strong>{json.loads((ROOT / "content" / folder / "curriculum.json").read_text())["title"]}</strong></a>'
        for _, folder, out, _ in APPS)
    css = (SRC / "style.css").read_text()
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Learning Apps</title>{FONTS}<style>{css}</style></head>
<body><main class="wrap stack"><h1 class="display">Learning Apps</h1>{links}
<p class="small muted">Tip: open an app, then use Share → Add to Home Screen to keep it like a regular app.</p></main></body></html>
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifact", type=pathlib.Path, help="also write artifact pages (data beside the page) here")
    args = ap.parse_args()

    DIST.mkdir(parents=True, exist_ok=True)
    for kind, folder, out, short in APPS:
        curriculum = json.loads((ROOT / "content" / folder / "curriculum.json").read_text())
        path = DIST / out
        path.write_text(standalone(kind, curriculum, short))
        print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB)")

        if args.artifact:
            d = args.artifact / kind
            d.mkdir(parents=True, exist_ok=True)
            (d / "index.html").write_text(head(curriculum["title"], short) + "\n" + page_body(kind, None) + "\n")
            (d / "curriculum.json").write_text(json.dumps(curriculum, ensure_ascii=False, separators=(",", ":")))
            print(f"wrote artifact page {d}/index.html")

    (DIST / "index.html").write_text(index_page())
    (DIST / ".nojekyll").write_text("")  # serve files as-is
    print(f"wrote {(DIST / 'index.html').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
