#!/usr/bin/env python3
"""Writes each version's notes from CHANGELOG.md into its appcast.xml entry, so Sparkle's
update window shows just those notes instead of loading a web page. Entries for versions
the changelog doesn't have are left alone. `make release` runs this."""

import importlib.util
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
APPCAST = ROOT / "appcast.xml"

# The changelog parser is the website's (changelog-page.py), so the two never disagree.
spec = importlib.util.spec_from_file_location("changelog_page", ROOT / "Scripts" / "changelog-page.py")
changelog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changelog)


def notes(intro, points):
    parts = [f"<p>{changelog.inline(p)}</p>" for p in intro]
    if points:
        parts.append("<ul>" + "".join(f"<li>{changelog.inline(p)}</li>" for p in points) + "</ul>")
    return "".join(parts)


def main():
    by_version = {version: notes(intro, points) for version, _, intro, points in changelog.releases()}

    def update(match):
        item = match.group(0)
        version = re.search(r"<sparkle:shortVersionString>([^<]+)<", item)
        if not version or version.group(1) not in by_version:
            return item
        description = f"<description><![CDATA[{by_version[version.group(1)]}]]></description>"
        item = re.sub(r"\n\s*<sparkle:releaseNotesLink>.*?</sparkle:releaseNotesLink>", "", item)
        item = re.sub(r"\n\s*<description>.*?</description>", "", item, flags=re.S)
        return re.sub(r"(\n(\s*)<title>.*?</title>)", lambda t: f"{t.group(1)}\n{t.group(2)}{description}", item, count=1)

    APPCAST.write_text(re.sub(r"<item>.*?</item>", update, APPCAST.read_text(), flags=re.S))
    print(f"Wrote release notes into {APPCAST.name}")


if __name__ == "__main__":
    main()
