#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" != 1 || ! -f "$1" ]]; then
    printf 'Usage: bash scripts/prepare-update.sh <bilingual-release-notes.md>\n' >&2
    printf 'Signs the existing release DMG and writes website/appcast.xml; does not publish.\n' >&2
    exit 2
fi
notes_path="$1"
app_path="$PWD/dist/Tessera.app"
bash scripts/verify-app-bundle.sh "$app_path"
tools="$(bash scripts/sparkle-tools.sh)"
account="io.github.jgoneit.tessera"
info="$app_path/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :TesseraReleaseVersion' "$info")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")"
# -p only looks up the existing public key. Missing keys must never silently
# produce a different signing identity for already installed applications.
existing_key="$("$tools/generate_keys" --account "$account" -p)"
[[ "$existing_key" == "$public_key" ]] || { printf 'Signing key does not match the app public key.\n' >&2; exit 1; }
architecture="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/Tessera")"
archive_name="Tessera-$version-${architecture// /+}.dmg"
archive="$PWD/dist/$archive_name"
[[ -f "$archive" ]] || { printf 'Missing release DMG: %s\n' "$archive" >&2; exit 1; }
/usr/bin/hdiutil verify "$archive"
work_dir="$(mktemp -d "$PWD/dist/.tessera-update.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
cp "$archive" "$work_dir/$archive_name"
cp "$notes_path" "$work_dir/${archive_name%.dmg}.md"
if [[ -f website/appcast.xml ]]; then cp website/appcast.xml "$work_dir/appcast.xml"; fi
channel_arguments=()
if [[ "$version" == *-alpha.* ]]; then channel_arguments=(--channel alpha); fi
"$tools/generate_appcast" --account "$account" --maximum-deltas 0 --maximum-versions 0 \
    --versions "$build" "${channel_arguments[@]}" --embed-release-notes \
    --download-url-prefix "https://github.com/jgoneit/tessera/releases/download/v$version/" \
    --link "https://jgoneit.github.io/tessera/" "$work_dir"
# Sparkle reads the numeric CFBundleShortVersionString. The feed display label
# follows Tessera's full prerelease name; re-sign after this deliberate edit.
python3 - "$work_dir/appcast.xml" "$build" "$version" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
path, build, release = sys.argv[1:]
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
tree = ET.parse(path)
for item in tree.getroot().findall('./channel/item'):
    if item.findtext(f'{{{namespace}}}version') == build:
        value = item.find(f'{{{namespace}}}shortVersionString')
        if value is None:
            value = ET.SubElement(item, f'{{{namespace}}}shortVersionString')
        value.text = release
        item.find('title').text = f'Tessera {release}'
tree.write(path, encoding='utf-8', xml_declaration=True)
PY
"$tools/sign_update" --account "$account" "$work_dir/appcast.xml"
swift scripts/verify-update.swift "$info" "$work_dir/appcast.xml" "$archive"
cp "$work_dir/appcast.xml" website/appcast.xml
(cd dist && shasum -a 256 "$archive_name" > SHA256SUMS)
printf 'Prepared signed website/appcast.xml and dist/SHA256SUMS. No files were published.\n'
