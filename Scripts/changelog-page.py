#!/usr/bin/env python3
"""Builds the website's changelog page (docs/changelog.html) from the Walnut sections of
CHANGELOG.md. The Hermes history further down stays on GitHub. `make release` runs this."""

import datetime
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "CHANGELOG.md"
PAGE = ROOT / "docs" / "changelog.html"
REPO = "https://github.com/brandbrook/WalnutPlayer"


def inline(text):
    """Escapes text for HTML, keeping `code` spans."""
    parts = re.split(r"`([^`]+)`", text)
    return "".join(f"<code>{html.escape(p)}</code>" if i % 2 else html.escape(p) for i, p in enumerate(parts))


def releases():
    """Yields (version, date, intro paragraphs, bullet points) for each Walnut release, newest first."""
    current = None
    for line in SOURCE.read_text().splitlines():
        heading = re.match(r"# Walnut (\S+) \((\d+)/(\d+)/(\d+)\)", line)
        if heading:
            if current:
                yield current
            version, month, day, year = heading.groups()
            date = datetime.date(2000 + int(year), int(month), int(day))
            current = (version, date, [], [])
        elif line.startswith("# "):            # the first Hermes version: Walnut's history ends here
            break
        elif current and line.startswith("* "):
            current[3].append(line[2:].strip())
        elif current and line.strip():
            current[2].append(line.strip())
    if current:
        yield current


def entry(version, date, intro, points):
    when = f"{date:%B} {date.day}, {date.year}"
    lines = [f'    <article class="release" id="v{html.escape(version)}">',
             f'      <header><h2>Walnut {html.escape(version)}</h2><time datetime="{date.isoformat()}">{when}</time></header>']
    lines += [f"      <p>{inline(p)}</p>" for p in intro]
    if points:
        lines.append("      <ul>")
        lines += [f"        <li>{inline(p)}</li>" for p in points]
        lines.append("      </ul>")
    lines.append("    </article>")
    return "\n".join(lines)


def page(entries):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>What's new in Walnut Player</title>
<meta name="description" content="Every version of Walnut, the free, open-source Pandora player for the Mac, and what changed in it.">
<meta property="og:title" content="What's new in Walnut Player">
<meta property="og:description" content="Every version of Walnut, the Pandora player built like a walnut table radio, and what changed in it.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://brandbrook.github.io/WalnutPlayer/changelog.html">
<meta property="og:site_name" content="Walnut Player">
<meta property="og:image" content="https://brandbrook.github.io/WalnutPlayer/og.jpg">
<meta name="twitter:card" content="summary_large_image">
<meta name="color-scheme" content="light dark">
<link rel="icon" href="favicon.png">
<link rel="apple-touch-icon" href="icon.png">
<!-- Generated from CHANGELOG.md by Scripts/changelog-page.py; edit those, not this file. -->
<style>
  :root {{
    --bg: #f6eedc;
    --surface: #fffaf0;
    --ink: #2e2012;
    --ink-soft: #6b5638;
    --brass: #b8904a;
    --line: rgba(110, 70, 15, 0.16);
    --button-ink: #2e1d0a;
    --serif: ui-serif, "New York", "Iowan Old Style", Georgia, serif;
    --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --bg: #140d07;
      --surface: #1f150c;
      --ink: #f3e3c2;
      --ink-soft: #c2a678;
      --brass: #d6b26a;
      --line: rgba(255, 210, 140, 0.14);
    }}
  }}
  * {{ box-sizing: border-box; }}
  html {{ -webkit-text-size-adjust: 100%; }}
  body {{ margin: 0; background: var(--bg); color: var(--ink); font: 17px/1.6 var(--sans); -webkit-font-smoothing: antialiased; }}
  a {{ color: inherit; text-underline-offset: 2px; }}
  .wrap {{ max-width: 760px; margin: 0 auto; padding: 0 24px; }}

  /* a slim strip of the hero's walnut */
  .top {{ position: relative; color: #f8ead0; background: #3a2414 url(walnut.jpg) center / cover; }}
  .top::before {{ content: ""; position: absolute; inset: 0; background: linear-gradient(180deg, rgba(20, 10, 2, 0.45), rgba(20, 10, 2, 0.75)); }}
  .top .wrap {{ position: relative; display: flex; align-items: center; justify-content: space-between; gap: 16px; padding-top: 18px; padding-bottom: 18px; }}
  .brand {{ display: inline-flex; align-items: center; gap: 12px; text-decoration: none; }}
  .brand img {{ width: 36px; height: 36px; }}
  .brand span {{ font: 600 14px/1 var(--sans); letter-spacing: 0.22em; text-transform: uppercase; color: #ecd7ad; }}
  .button {{
    display: inline-flex; align-items: center; padding: 10px 20px; border-radius: 999px;
    font: 600 15px/1 var(--sans); text-decoration: none; color: var(--button-ink);
    background: linear-gradient(135deg, #f0d79a, #c9a35c 55%, #9c7634);
    box-shadow: inset 0 1px 0 rgba(255, 248, 222, 0.6), 0 2px 6px rgba(10, 5, 0, 0.45);
  }}
  .button:hover {{ filter: brightness(1.06); }}

  main {{ padding: 56px 0 72px; }}
  h1 {{ font: 600 clamp(32px, 5vw, 44px)/1.1 var(--serif); margin: 0 0 8px; }}
  .intro {{ color: var(--ink-soft); margin: 0 0 40px; }}
  .release {{ background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 22px 24px; margin-bottom: 18px; }}
  .release header {{ display: flex; align-items: baseline; justify-content: space-between; gap: 4px 16px; flex-wrap: wrap; margin-bottom: 8px; }}
  .release h2 {{ font: 600 22px/1.25 var(--serif); margin: 0; }}
  .release time {{ font-size: 14px; color: var(--ink-soft); }}
  .release p {{ margin: 0 0 8px; color: var(--ink-soft); }}
  .release ul {{ margin: 0; padding-left: 1.2em; }}
  .release li {{ margin: 4px 0; }}
  .release li::marker {{ color: var(--brass); }}
  .older {{ color: var(--ink-soft); font-size: 15px; margin: 28px 0 0; }}
  code {{ font: 14px ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--bg); border: 1px solid var(--line); border-radius: 6px; padding: 1px 6px; }}

  footer {{ border-top: 1px solid var(--line); padding: 28px 0 40px; font-size: 14px; color: var(--ink-soft); }}
  footer .wrap {{ display: flex; justify-content: space-between; align-items: baseline; gap: 8px 24px; flex-wrap: wrap; }}
  footer p {{ margin: 0; }}
  footer a {{ color: var(--ink); }}
  .foot-links {{ display: flex; gap: 18px; flex-wrap: wrap; }}
  .sr-only {{ position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0; }}

  @media (max-width: 760px) {{
    .wrap {{ padding: 0 16px; }}
    main {{ padding: 40px 0 52px; }}
    .release {{ padding: 18px; }}
  }}
</style>
</head>
<body>

<div class="top">
  <div class="wrap">
    <a class="brand" href="./"><img src="icon.png" alt=""><span>Walnut Player</span></a>
    <a class="button" href="{REPO}/releases/latest">Download</a>
  </div>
</div>

<main>
  <div class="wrap">
    <h1>What's new</h1>
    <p class="intro">Every version of Walnut, newest first. Walnut checks for updates by itself, or choose <em>Check for Updates…</em> in the Walnut menu.</p>
{chr(10).join(entries)}
    <p class="older">Walnut is built on Hermes; its earlier history is in the <a href="{REPO}/blob/master/CHANGELOG.md">full changelog on GitHub</a>.</p>
  </div>
</main>

<footer>
  <div class="wrap">
    <p>Walnut is free and open source, based on <a href="https://github.com/HermesApp/Hermes">Hermes</a>. Built by <a href="https://iamradu.com/" rel="me noopener" target="_blank">Radu<span class="sr-only"> (opens in a new tab)</span></a>.</p>
    <p class="foot-links"><a href="./">Home</a><a href="{REPO}/issues">Report an issue</a><a href="{REPO}/blob/master/LICENSE">MIT License</a></p>
  </div>
</footer>

</body>
</html>
"""


PAGE.write_text(page([entry(*r) for r in releases()]))
print(f"Wrote {PAGE.relative_to(ROOT)}")
