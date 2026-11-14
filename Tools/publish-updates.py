#!/usr/bin/env python3
"""Publish a signed Sparkle ZIP and web DMG over SFTP; retain the two newest versions."""

import copy
import argparse
import datetime
import hashlib
import html
import json
import shutil
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

BASE = "https://updates.sensebar.site"
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", NS)
ZIP_NAME = re.compile(r"SenseBar-v\d+\.\d+\.\d+-macOS-Universal\.zip")
DMG_NAME = re.compile(r"SenseBar-v\d+\.\d+\.\d+-macOS-Universal\.dmg")


def release_notes(version, changelog):
    """Validate structured YAML and render only the requested version as Markdown."""
    try:
        import yaml
    except ImportError as error:
        raise RuntimeError("Install the release dependency: python3 -m pip install PyYAML==6.0.3") from error

    class ChangelogLoader(yaml.SafeLoader):
        def construct_mapping(self, node, deep=False):
            result = {}
            for key_node, value_node in node.value:
                key = self.construct_object(key_node, deep=deep)
                if not isinstance(key, str) or key in result:
                    raise ValueError(f"changelog.yaml: invalid or duplicate field {key!r}")
                result[key] = self.construct_object(value_node, deep=deep)
            return result

    data = yaml.load(changelog, Loader=ChangelogLoader)
    if not isinstance(data, dict) or set(data) != {"releases"}:
        raise ValueError("changelog.yaml must contain a 'releases' list")
    releases = data["releases"]
    if not isinstance(releases, list) or not releases:
        raise ValueError("changelog.yaml releases must be a nonempty list")
    labels = {"feature": "Tính năng mới", "improvement": "Cải thiện", "fix": "Sửa lỗi", "other": "Khác"}
    versions = set()
    selected = None
    for release in releases:
        if not isinstance(release, dict) or set(release) - {"version", "date", "changes"}:
            raise ValueError("Each release must contain version, optional date, and changes")
        release_version = release.get("version")
        if not isinstance(release_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", release_version):
            raise ValueError("Each release version must be a quoted X.Y.Z string")
        if release_version in versions:
            raise ValueError(f"Duplicate release version: {release_version}")
        versions.add(release_version)
        date = release.get("date")
        if date is not None:
            if not isinstance(date, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
                raise ValueError(f"{release_version}: date must be a quoted YYYY-MM-DD string")
            datetime.date.fromisoformat(date)
        changes = release.get("changes")
        if not isinstance(changes, list) or not changes:
            raise ValueError(f"{release_version}: changes must be a nonempty list")
        for change in changes:
            if not isinstance(change, dict) or set(change) != {"type", "text"}:
                raise ValueError(f"{release_version}: each change must contain type and text")
            if not isinstance(change["type"], str) or change["type"] not in labels:
                raise ValueError(f"{release_version}: type must be feature, improvement, fix, or other")
            if not isinstance(change["text"], str) or not change["text"].strip():
                raise ValueError(f"{release_version}: change text must be nonempty")
        if release_version == version:
            selected = release
    if selected is None:
        raise ValueError(f"changelog.yaml has no notes for version {version}")
    lines = [f"# SenseBar {version}", ""]
    if selected.get("date"):
        lines += [f"Ngày phát hành: {selected['date']}", ""]
    for kind, title in labels.items():
        entries = [change for change in selected["changes"] if change["type"] == kind]
        if entries:
            lines += [f"## {title}", ""]
            lines += ["- " + " ".join(change["text"].split()) for change in entries]
            lines.append("")
    return "\n".join(lines)


def prepare_release_notes(version):
    notes = release_notes(version, Path("changelog.yaml").read_text(encoding="utf-8"))
    Path("build").mkdir(exist_ok=True)
    Path("build/RELEASE_NOTES.md").write_text(notes, encoding="utf-8")


def sparkle_notes(version, notes):
    """Compact HTML for Sparkle; keep full Markdown headings on GitHub only."""
    heading, _, body = notes.partition("\n")
    if heading != f"# SenseBar {version}" or not body.strip():
        raise ValueError("Sparkle release notes must match the requested version")
    content = []
    in_list = False
    for line in body.splitlines():
        if not line.strip():
            continue
        if line.startswith("- "):
            if not in_list:
                content.append("<ul>")
                in_list = True
            content.append(f"<li>{html.escape(line[2:])}</li>")
        else:
            if in_list:
                content.append("</ul>")
                in_list = False
            if line.startswith("## "):
                content.append(f"<h2>{html.escape(line[3:])}</h2>")
            else:
                content.append(f"<p>{html.escape(line)}</p>")
    if in_list:
        content.append("</ul>")
    return f'''<!doctype html>
<html lang="vi"><head><meta charset="utf-8">
<meta name="sensebar-version" content="{html.escape(version, quote=True)}">
<meta name="color-scheme" content="light dark">
<style>
:root {{ color-scheme: light dark; }}
body {{ margin: 10px 12px; font: 13px/1.5 -apple-system, BlinkMacSystemFont, sans-serif;
        color: #252525; background: transparent; -webkit-text-size-adjust: 100%; }}
h2 {{ font-size: 13px; font-weight: 600; line-height: 1.4; margin: 12px 0 5px; }}
h2:first-child {{ margin-top: 0; }}
ul {{ margin: 0 0 10px; padding-left: 18px; }}
li {{ margin: 3px 0; }}
p {{ margin: 0 0 8px; color: #626262; font-size: 12px; }}
@media (prefers-color-scheme: dark) {{ body {{ color: #ededed; }} p {{ color: #b6b6b6; }} }}
</style></head><body>
{''.join(content)}
</body></html>'''


def prepare_preview_notes():
    """Use the production renderer for every version offered by Debug preview."""
    import yaml
    source = Path("changelog.yaml").read_text(encoding="utf-8")
    data = yaml.safe_load(source)
    if not isinstance(data, dict) or not isinstance(data.get("releases"), list) or not data["releases"]:
        raise ValueError("changelog.yaml must contain a nonempty releases list")
    notes = {}
    for release in data["releases"]:
        version = release.get("version") if isinstance(release, dict) else None
        notes[version] = sparkle_notes(version, release_notes(version, source))
    Path("build").mkdir(exist_ok=True)
    Path("build/UpdatePreviewNotes.json").write_text(
        json.dumps(notes, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def verify_appcast_notes(item, notes):
    description = item.find("description")
    if (description is None or description.attrib.get(f"{{{NS}}}format", "html") != "html"
            or (description.text or "").strip() != notes.strip()):
        raise ValueError("Generated appcast release notes do not match changelog.yaml output; refusing upload")


def fetch(url):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def sha256_digest(path):
    """Compute the SHA-256 digest of a file without loading large binaries into memory."""
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.digest()


def upload_and_verify_asset(path, remote):
    """Upload a release asset atomically via SFTP and verify its public HTTPS SHA-256."""
    sftp([
        f'put "{path.resolve()}" "{remote}/{path.name}.uploading"',
        f'rename "{remote}/{path.name}.uploading" "{remote}/{path.name}"',
    ])
    expected = sha256_digest(path)
    request = urllib.request.Request(
        f"{BASE}/releases/{path.name}",
        headers={"Cache-Control": "no-cache"},
    )
    actual = hashlib.sha256()
    with urllib.request.urlopen(request, timeout=120) as response:
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            actual.update(chunk)
    if actual.digest() != expected:
        kind = path.suffix.lstrip(".").upper() or "asset"
        raise ValueError(
            f"Public {kind} checksum mismatch; leaving current feed and archives intact"
        )

def sftp(commands):
    result = subprocess.run([
        "sftp", "-b", "-", "-P", os.environ["SFTP_PORT"],
        "-oBatchMode=yes", "-oStrictHostKeyChecking=yes", "-oIdentitiesOnly=yes",
        "-i", str(Path.home() / ".ssh/sensebar_deploy"),
        f'{os.environ["SFTP_USER"]}@{os.environ["SFTP_HOST"]}',
    ], input="\n".join(commands) + "\n", text=True, capture_output=True, check=True)
    return result.stdout


def main():
    remote = os.environ["SFTP_REMOTE_DIR"].rstrip("/")
    if remote != "/public/releases":
        raise ValueError("Expected chroot SFTP_REMOTE_DIR=/public/releases")
    with open("build/SenseBar.app/Contents/Info.plist", "rb") as source:
        info = plistlib.load(source)
    version = info["CFBundleShortVersionString"]
    build = int(info["CFBundleVersion"])
    archive = Path(f"build/SenseBar-v{version}-macOS-Universal.zip")
    dmg_archive = Path(f"build/SenseBar-v{version}-macOS-Universal.dmg")
    if not ZIP_NAME.fullmatch(archive.name):
        raise ValueError("Unexpected ZIP filename")
    if not DMG_NAME.fullmatch(dmg_archive.name):
        raise ValueError("Unexpected DMG filename")
    for asset in (archive, dmg_archive):
        if not asset.is_file():
            raise ValueError(f"Missing release asset: {asset}")
    notes = Path("build/RELEASE_NOTES.md").read_text(encoding="utf-8")
    heading, _, body = notes.partition("\n")
    if heading.strip() != f"# SenseBar {version}" or not body.strip():
        raise ValueError("Release notes must match the app version and describe changes for users")
    display_notes = sparkle_notes(version, notes)

    try:
        previous = ET.fromstring(fetch(BASE + "/appcast.xml"))
        old_items = previous.findall("channel/item")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        old_items = []

    # Validate the previous feed before uploading or deleting anything.
    old_items.sort(key=lambda item: int(item.findtext(f"{{{NS}}}version")), reverse=True)
    if old_items and int(old_items[0].findtext(f"{{{NS}}}version")) >= build:
        raise ValueError("Feed build must increase; refusing an overwrite or downgrade")
    retained = old_items[:1]
    keep = {archive.name, dmg_archive.name}
    for item in retained:
        enclosure = item.find("enclosure")
        name = enclosure.attrib["url"].removeprefix(BASE + "/releases/")
        if not ZIP_NAME.fullmatch(name):
            raise ValueError("Unexpected existing feed enclosure URL")
        keep.add(name)
        keep.add(Path(name).with_suffix(".dmg").name)
        # Confirm the fallback archive is still available before publishing it.
        request = urllib.request.Request(enclosure.attrib["url"], method="HEAD")
        with urllib.request.urlopen(request, timeout=30):
            pass

    tools = Path(".build/artifacts/sparkle/Sparkle/bin").resolve()
    feed = Path("build/appcast.xml")
    with tempfile.TemporaryDirectory(prefix="sensebar-appcast-") as directory:
        staging = Path(directory)
        shutil.copy2(archive, staging / archive.name)
        rss = ET.Element("rss", version="2.0")
        # ElementTree only declares namespaces used by existing elements.
        # An empty first-release feed still needs this declaration because
        # generate_appcast reuses it when adding sparkle-prefixed elements.
        if not retained:
            rss.set("xmlns:sparkle", NS)
        channel = ET.SubElement(rss, "channel")
        ET.SubElement(channel, "title").text = "SenseBar Updates"
        for old in retained:
            channel.append(copy.deepcopy(old))
        ET.ElementTree(rss).write(staging / "appcast.xml", encoding="utf-8", xml_declaration=True)
        (staging / archive.with_suffix(".html").name).write_text(display_notes, encoding="utf-8")
        subprocess.run([
            str(tools / "generate_appcast"), "--ed-key-file", "-",
            "--download-url-prefix", BASE + "/releases/",
            "--maximum-versions", "2", "--maximum-deltas", "0",
            "--embed-release-notes", "--link", "https://sensebar.site",
            str(staging),
        ], input=os.environ["SPARKLE_PRIVATE_KEY"].strip() + "\n", text=True, check=True)
        shutil.copy2(staging / "appcast.xml", feed)
    items = ET.parse(feed).findall("channel/item")
    if len(items) != 1 + len(retained):
        raise ValueError("Unexpected number of generated feed entries")
    current = next(item for item in items if item.findtext(f"{{{NS}}}version") == str(build))
    verify_appcast_notes(current, display_notes)
    enclosure = current.find("enclosure")
    if enclosure.attrib["url"] != f"{BASE}/releases/{archive.name}":
        raise ValueError("Unexpected generated download URL")
    if int(enclosure.attrib["length"]) != archive.stat().st_size:
        raise ValueError("Unexpected generated archive length")
    subprocess.run([
        "swift", "-", info["SUPublicEDKey"], enclosure.attrib[f"{{{NS}}}edSignature"], str(archive),
    ], input="import CryptoKit\nimport Foundation\n\n// Verify the generated archive signature against the key shipped in Info.plist.\nlet arguments = CommandLine.arguments\nguard arguments.count == 4,\n      let publicKey = Data(base64Encoded: arguments[1]),\n      let signature = Data(base64Encoded: arguments[2]) else {\n    fatalError(\"Expected public key, signature, archive path\")\n}\nlet key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)\nlet archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .mappedIfSafe)\nguard key.isValidSignature(signature, for: archive) else {\n    fatalError(\"Sparkle signing key does not match the app's SUPublicEDKey\")\n}\nprint(\"Sparkle EdDSA signature verified\")\n", text=True, check=True)

    # Upload Sparkle ZIP and web DMG via temporary names before updating appcast.xml.
    upload_and_verify_asset(archive, remote)
    upload_and_verify_asset(dmg_archive, remote)
    sftp([f'put "{feed.resolve()}" "/public/appcast.xml.uploading"',
          'rename "/public/appcast.xml.uploading" "/public/appcast.xml"'])
    if fetch(BASE + "/appcast.xml") != feed.read_bytes():
        raise ValueError("Public feed mismatch; skipping cleanup")

    # Only delete exact SenseBar ZIP/DMG names after all public downloads verify.
    listing = sftp([f'ls -1 "{remote}"'])
    remove = []
    for line in listing.splitlines():
        name = line.strip().removeprefix(remote + "/")
        if (ZIP_NAME.fullmatch(name) or DMG_NAME.fullmatch(name)) and name not in keep:
            remove.append(f'rm "{remote}/{name}"')
    if remove:
        sftp(remove)
    print(f"Published {version}; retained: {', '.join(sorted(keep))}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--prepare-notes", metavar="VERSION", help="Generate user-facing notes from changelog.yaml")
    mode.add_argument("--prepare-preview-notes", action="store_true", help="Generate Debug preview notes using the same renderer")
    arguments = parser.parse_args()
    if arguments.prepare_notes:
        prepare_release_notes(arguments.prepare_notes)
    elif arguments.prepare_preview_notes:
        prepare_preview_notes()
    else:
        main()
