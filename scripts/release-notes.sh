#!/usr/bin/env bash
# Format and assemble cumulative Sparkle 2 HTML release notes (capped at the last 10 versions).
#
# In Sparkle 2 (`SPUUserDriver.h` / `SUUpdateAlert`), `-showUpdateFoundWithAppcastItem:state:reply:`
# only receives the single winning `SUAppcastItem` and `SUReleaseNotesView` renders only that item's
# `<description><![CDATA[...]]></description>`. Sparkle never concatenates `<description>` across
# multiple `<item>` elements in `appcast.xml`.
#
# This script renders the new version's release notes at the top under an `<h3>` heading and carries
# forward previous versions' sections below it (from the previous `appcast.xml`, prior release
# `appcast.xml` assets, and/or recent GitHub Releases), deduplicating by version string and capping
# at `SAGA_MAX_RELEASE_NOTES_VERSIONS` (10).
#
# Usage:
#   ./scripts/release-notes.sh <version> [raw-notes]
#
# Environment variables:
#   SAGA_RELEASE_NOTES              — Markdown or HTML release notes for `<version>` (if arg 2 omitted)
#   SAGA_PREVIOUS_APPCAST           — Optional local path or URL to previous `appcast.xml`
#   SAGA_RELEASES_JSON              — Optional local path or JSON string of GitHub Releases array
#   SAGA_FETCH_PREVIOUS_NOTES       — Set to `0` to skip network fetches for previous appcast / releases (default: `1`)
#   SAGA_MAX_RELEASE_NOTES_VERSIONS — Maximum versions to include in cumulative output (default: `10`)
#   SAGA_REPO                       — GitHub repository (default: `dgattey/saga`)
set -euo pipefail

VERSION="${1:?release-notes: version is required (arg 1)}"
if [[ $# -ge 2 ]]; then
  export SAGA_RELEASE_NOTES="$2"
fi

exec python3 - "$VERSION" <<'PY'
import html
import json
import os
import re
import subprocess
import sys
import urllib.request
from typing import Dict, List, Optional, Tuple

new_version = sys.argv[1].strip().lstrip("v")
raw_new_notes = os.environ.get("SAGA_RELEASE_NOTES", "")
repo = os.environ.get("SAGA_REPO", "dgattey/saga").strip() or "dgattey/saga"
max_versions = int(os.environ.get("SAGA_MAX_RELEASE_NOTES_VERSIONS", "10"))
fetch_remote = os.environ.get("SAGA_FETCH_PREVIOUS_NOTES", "1") != "0"

NEW_H3_STYLE = "margin: 0 0 6px 0; font-size: 13px;"
PREV_H3_STYLE = "margin: 14px 0 6px 0; font-size: 13px; opacity: 0.75;"
LI_STYLE = "margin-bottom: 6px; line-height: 1.45;"

PATH_EXT_RE = re.compile(
    r"^("
    r"[/\.]\S+|"
    r"(?:Saga|scripts|server|\.github)/\S*|"
    r"\S+\.(?:swift|ts|tsx|js|mjs|css|json|yml|yaml|sh|md|plist|entitlements|pbxproj|xcframework|png|jpg|jpeg|svg|ico|xml)|"
    r"npm\s+test"
    r")$"
)


def is_noise_paren(inner: str) -> bool:
    cleaned = inner.strip()
    if not cleaned:
        return True
    parts = re.split(r"\s*(?:,|\band\b|\bor\b)\s*", cleaned)
    for part in parts:
        token = part.strip().strip("`").strip()
        if not token or not PATH_EXT_RE.match(token):
            return False
    return True


def strip_file_path_parens(text: str) -> str:
    def repl(match: re.Match) -> str:
        inner = match.group(1)
        if is_noise_paren(inner):
            return ""
        return match.group(0)

    out = re.sub(r"\s*\(([^()]+)\)", repl, text)
    out = re.sub(r"\s+([,.;:])", r"\1", out)
    out = re.sub(r"  +", " ", out)
    return out.strip()


def render_inline(text: str) -> str:
    text = strip_file_path_parens(text)
    escaped = html.escape(text, quote=False)
    escaped = re.sub(
        r"\[([^\]]+)\]\((https?://[^\s)]+)\)",
        r'<a href="\2">\1</a>',
        escaped,
    )
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return escaped


def extract_section(text: str, heading: str) -> str:
    lines = text.splitlines()
    in_section = False
    collected = []
    heading_re = re.compile(rf"^#+\s*{re.escape(heading)}\s*$", re.IGNORECASE)
    any_heading_re = re.compile(r"^#+\s+\S")
    hr_re = re.compile(r"^-+\s*$")
    for line in lines:
        if heading_re.match(line.strip()):
            in_section = True
            continue
        if in_section:
            if any_heading_re.match(line.strip()) or hr_re.match(line.strip()):
                break
            collected.append(line)
    cleaned = [l for l in collected if not re.match(r"^\s*[-*]\s*$", l)]
    return "\n".join(cleaned).strip()


def strip_outer_h3(fragment: str) -> str:
    return re.sub(
        r"^\s*<h3\b[^>]*>[\s\S]*?</h3>\s*",
        "",
        fragment.strip(),
        count=1,
        flags=re.IGNORECASE,
    ).strip()


def is_already_html_block(text: str) -> bool:
    stripped = strip_outer_h3(text)
    return bool(re.match(r"^\s*<(?:ul|ol|p)\b", stripped, re.IGNORECASE))


def format_single_version_body(raw_input: str, version: str) -> str:
    raw = re.sub(r"<!--[\s\S]*?-->", "", raw_input or "").strip()

    for section_name in ("Release notes", "Highlights", "What changed?"):
        extracted = extract_section(raw, section_name)
        if extracted:
            raw = extracted
            break

    if is_already_html_block(raw):
        cleaned_html = strip_outer_h3(raw)
        if cleaned_html:
            return cleaned_html

    lines = raw.splitlines()
    bullets: List[str] = []
    paragraphs: List[str] = []
    current_bullet: Optional[str] = None

    for line in lines:
        stripped = line.strip()
        if not stripped:
            if current_bullet is not None:
                bullets.append(current_bullet)
                current_bullet = None
            continue
        if re.match(r"^!\[[^\]]*\]\([^)]+\)$", stripped) or re.match(
            r"^<(?:img|video)\b", stripped, re.IGNORECASE
        ):
            continue
        if re.match(r"^#+\s+", stripped):
            continue
        bullet_match = re.match(r"^[-*]\s+(.+)$", stripped)
        if bullet_match:
            if current_bullet is not None:
                bullets.append(current_bullet)
            current_bullet = bullet_match.group(1).strip()
        elif current_bullet is not None:
            current_bullet = f"{current_bullet} {stripped}"
        else:
            paragraphs.append(stripped)

    if current_bullet is not None:
        bullets.append(current_bullet)

    # Filter out bare heading-only parent bullets when sub-bullets were flattened into top-level bullets
    filtered_bullets = [
        b
        for b in bullets
        if not re.match(r"^(?:\*\*[^*]+\*\*|[^:]{1,60}):\s*$", b.strip())
    ]
    if filtered_bullets:
        bullets = filtered_bullets

    out_parts: List[str] = []
    if paragraphs:
        for p in paragraphs:
            out_parts.append(
                f'<p style="margin: 0 0 8px 0; line-height: 1.45;">{render_inline(p)}</p>'
            )
    if bullets:
        out_parts.append("<ul>")
        for b in bullets:
            out_parts.append(f'  <li style="{LI_STYLE}">{render_inline(b)}</li>')
        out_parts.append("</ul>")

    if not out_parts:
        out_parts.append("<ul>")
        out_parts.append(
            f'  <li style="{LI_STYLE}">Release v{html.escape(version)}</li>'
        )
        out_parts.append("</ul>")

    return "\n".join(out_parts)


def normalize_version(v: str) -> str:
    v = html.unescape(v or "").strip()
    if v.lower().startswith("version "):
        v = v[8:].strip()
    return v.lstrip("v").strip()


def parse_appcast_sections(xml_text: str) -> List[Tuple[str, str]]:
    if not xml_text or not xml_text.strip():
        return []

    sections: List[Tuple[str, str]] = []
    item_matches = list(
        re.finditer(r"<item\b[^>]*>([\s\S]*?)</item>", xml_text, re.IGNORECASE)
    )
    blocks = [m.group(1) for m in item_matches] if item_matches else [xml_text]

    for block in blocks:
        short_ver_match = re.search(
            r"<sparkle:shortVersionString>\s*([^<]+?)\s*</sparkle:shortVersionString>",
            block,
            re.IGNORECASE,
        )
        if not short_ver_match:
            short_ver_match = re.search(
                r"<title>\s*([^<]+?)\s*</title>", block, re.IGNORECASE
            )
        item_version = (
            normalize_version(short_ver_match.group(1)) if short_ver_match else ""
        )

        desc_match = re.search(
            r"<description>\s*(?:<!\[CDATA\[([\s\S]*?)\]\]>|([\s\S]*?))\s*</description>",
            block,
            re.IGNORECASE,
        )
        if not desc_match:
            continue

        desc_raw = (
            desc_match.group(1)
            if desc_match.group(1) is not None
            else html.unescape(desc_match.group(2) or "")
        ).strip()
        if not desc_raw:
            continue

        h3_matches = list(
            re.finditer(
                r"<h3\b[^>]*>([\s\S]*?)</h3>", desc_raw, flags=re.IGNORECASE
            )
        )
        if h3_matches:
            for idx, match in enumerate(h3_matches):
                heading_text = re.sub(r"<[^>]+>", "", match.group(1)).strip()
                ver = normalize_version(heading_text)
                if not ver:
                    continue
                body_start = match.end()
                body_end = (
                    h3_matches[idx + 1].start()
                    if idx + 1 < len(h3_matches)
                    else len(desc_raw)
                )
                body_segment = desc_raw[body_start:body_end].strip()
                if body_segment:
                    formatted_body = format_single_version_body(body_segment, ver)
                    sections.append((ver, formatted_body))
        elif item_version:
            formatted_body = format_single_version_body(desc_raw, item_version)
            sections.append((item_version, formatted_body))

    return sections


def fetch_url_text(url: str, timeout: float = 8.0) -> Optional[str]:
    try:
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": "Saga-Release-Notes/1.0",
                "Accept": "application/rss+xml, application/xml, text/xml, */*",
            },
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if 200 <= resp.status < 300:
                return resp.read().decode("utf-8", errors="replace")
    except Exception:
        return None
    return None


def load_previous_appcast_xml() -> str:
    source = os.environ.get("SAGA_PREVIOUS_APPCAST", "").strip()
    if source:
        if os.path.isfile(source):
            try:
                with open(source, "r", encoding="utf-8") as f:
                    return f.read()
            except Exception:
                return ""
        if source.startswith("http://") or source.startswith("https://"):
            return fetch_url_text(source) or ""
        if "<rss" in source or "<item" in source or "<description" in source:
            return source

    if not fetch_remote:
        return ""

    for url in (
        f"https://github.com/{repo}/releases/latest/download/appcast.xml",
        "https://saga.gattey.com/appcast.xml",
    ):
        text = fetch_url_text(url)
        if text and "<item" in text:
            return text
    return ""


def load_github_releases() -> List[Tuple[str, str, Optional[str]]]:
    releases_override = os.environ.get("SAGA_RELEASES_JSON", "").strip()
    raw_json = ""
    if releases_override:
        if os.path.isfile(releases_override):
            try:
                with open(releases_override, "r", encoding="utf-8") as f:
                    raw_json = f.read()
            except Exception:
                raw_json = ""
        else:
            raw_json = releases_override
    elif fetch_remote:
        try:
            proc = subprocess.run(
                ["gh", "api", f"repos/{repo}/releases?per_page={max(max_versions * 2, 15)}"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            if proc.returncode == 0 and proc.stdout.strip():
                raw_json = proc.stdout
        except Exception:
            raw_json = ""

        if not raw_json:
            api_url = f"https://api.github.com/repos/{repo}/releases?per_page={max(max_versions * 2, 15)}"
            headers = {
                "User-Agent": "Saga-Release-Notes/1.0",
                "Accept": "application/vnd.github+json",
            }
            token = (
                os.environ.get("GH_TOKEN")
                or os.environ.get("GITHUB_TOKEN")
                or ""
            ).strip()
            if token:
                headers["Authorization"] = f"Bearer {token}"
            try:
                req = urllib.request.Request(api_url, headers=headers)
                with urllib.request.urlopen(req, timeout=10) as resp:
                    if 200 <= resp.status < 300:
                        raw_json = resp.read().decode("utf-8", errors="replace")
            except Exception:
                raw_json = ""

    if not raw_json:
        return []

    try:
        payload = json.loads(raw_json)
    except Exception:
        return []

    if not isinstance(payload, list):
        return []

    results: List[Tuple[str, str, Optional[str]]] = []
    for rel in payload:
        if not isinstance(rel, dict):
            continue
        if rel.get("draft") or rel.get("prerelease"):
            continue
        ver = normalize_version(str(rel.get("tag_name") or rel.get("name") or ""))
        body = str(rel.get("body") or "").strip()
        if not ver:
            continue
        appcast_asset_url: Optional[str] = None
        assets = rel.get("assets")
        if isinstance(assets, list):
            for asset in assets:
                if isinstance(asset, dict) and asset.get("name") == "appcast.xml":
                    url = str(asset.get("browser_download_url") or "").strip()
                    if url:
                        appcast_asset_url = url
                        break
        results.append((ver, body, appcast_asset_url))
    return results


sections_by_version: List[Tuple[str, str]] = []
seen_versions = set()


def add_section(version_str: str, body_html: str) -> None:
    norm = normalize_version(version_str)
    if not norm or norm in seen_versions:
        return
    if len(sections_by_version) >= max_versions:
        return
    seen_versions.add(norm)
    sections_by_version.append((norm, body_html.strip()))


# 1. Always place the new version first
add_section(new_version, format_single_version_body(raw_new_notes, new_version))

# 2. Carry forward sections from previous appcast.xml (wrapping headerless <ul> with shortVersionString)
prev_xml = load_previous_appcast_xml()
for ver, body_html in parse_appcast_sections(prev_xml):
    add_section(ver, body_html)

# 3. Backfill additional historical versions from GitHub Releases if under max_versions
if len(sections_by_version) < max_versions:
    for ver, body_md, appcast_asset_url in load_github_releases():
        if len(sections_by_version) >= max_versions:
            break
        if ver in seen_versions:
            continue
        # Prefer the release's own appcast.xml description when available (preserves concise # Release notes)
        if fetch_remote and appcast_asset_url:
            rel_appcast_xml = fetch_url_text(appcast_asset_url, timeout=5.0)
            if rel_appcast_xml:
                parsed_rel_sections = parse_appcast_sections(rel_appcast_xml)
                if parsed_rel_sections:
                    for rel_ver, rel_body_html in parsed_rel_sections:
                        add_section(rel_ver, rel_body_html)
                    if ver in seen_versions:
                        continue
        if body_md:
            add_section(ver, format_single_version_body(body_md, ver))

rendered_blocks: List[str] = []
for idx, (ver, body_html) in enumerate(sections_by_version):
    h3_style = NEW_H3_STYLE if idx == 0 else PREV_H3_STYLE
    rendered_blocks.append(
        f'<h3 style="{h3_style}">{html.escape(ver)}</h3>\n{body_html}'
    )

print("\n".join(rendered_blocks))
PY
