#!/usr/bin/env python3
"""Publish a signed Sparkle ZIP over SFTP; retain the two newest feed entries."""

import copy
import hashlib
import html
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


def fetch(url):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


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
    if not ZIP_NAME.fullmatch(archive.name):
        raise ValueError("Unexpected ZIP filename")

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
    keep = {archive.name}
    for item in retained:
        enclosure = item.find("enclosure")
        name = enclosure.attrib["url"].removeprefix(BASE + "/releases/")
        if not ZIP_NAME.fullmatch(name):
            raise ValueError("Unexpected existing feed enclosure URL")
        keep.add(name)
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
        notes = html.escape(Path("build/RELEASE_NOTES.md").read_text())
        (staging / archive.with_suffix(".html").name).write_text("<pre>" + notes + "</pre>")
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
    enclosure = current.find("enclosure")
    if enclosure.attrib["url"] != f"{BASE}/releases/{archive.name}":
        raise ValueError("Unexpected generated download URL")
    if int(enclosure.attrib["length"]) != archive.stat().st_size:
        raise ValueError("Unexpected generated archive length")
    subprocess.run([
        "swift", "-", info["SUPublicEDKey"], enclosure.attrib[f"{{{NS}}}edSignature"], str(archive),
    ], input="import CryptoKit\nimport Foundation\n\n// Verify the generated archive signature against the key shipped in Info.plist.\nlet arguments = CommandLine.arguments\nguard arguments.count == 4,\n      let publicKey = Data(base64Encoded: arguments[1]),\n      let signature = Data(base64Encoded: arguments[2]) else {\n    fatalError(\"Expected public key, signature, archive path\")\n}\nlet key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)\nlet archive = try Data(contentsOf: URL(fileURLWithPath: arguments[3]), options: .mappedIfSafe)\nguard key.isValidSignature(signature, for: archive) else {\n    fatalError(\"Sparkle signing key does not match the app's SUPublicEDKey\")\n}\nprint(\"Sparkle EdDSA signature verified\")\n", text=True, check=True)

    # Upload to temporary names, then rename within the same filesystem.
    sftp([f'put "{archive.resolve()}" "{remote}/{archive.name}.uploading"',
          f'rename "{remote}/{archive.name}.uploading" "{remote}/{archive.name}"'])
    expected = hashlib.sha256(archive.read_bytes()).digest()
    request = urllib.request.Request(f"{BASE}/releases/{archive.name}")
    actual = hashlib.sha256()
    with urllib.request.urlopen(request, timeout=120) as response:
        for chunk in iter(lambda: response.read(1024 * 1024), b""):
            actual.update(chunk)
    if actual.digest() != expected:
        raise ValueError("Public ZIP checksum mismatch; leaving current feed and archives intact")
    sftp([f'put "{feed.resolve()}" "/public/appcast.xml.uploading"',
          'rename "/public/appcast.xml.uploading" "/public/appcast.xml"'])
    if fetch(BASE + "/appcast.xml") != feed.read_bytes():
        raise ValueError("Public feed mismatch; skipping cleanup")

    # Only delete exact SenseBar ZIP names after BOTH public downloads verify.
    listing = sftp([f'ls -1 "{remote}"'])
    remove = []
    for line in listing.splitlines():
        name = line.strip().removeprefix(remote + "/")
        if ZIP_NAME.fullmatch(name) and name not in keep:
            remove.append(f'rm "{remote}/{name}"')
    if remove:
        sftp(remove)
    print(f"Published {version}; retained: {', '.join(sorted(keep))}")


if __name__ == "__main__":
    main()
