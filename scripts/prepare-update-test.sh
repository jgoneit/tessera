#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
port="${1:-8769}"
if [[ "$#" -gt 1 || ! "$port" =~ ^[0-9]+$ || "$port" -lt 1024 || "$port" -gt 65535 ]]; then
    printf 'Usage: bash scripts/prepare-update-test.sh [loopback-port]\n' >&2
    exit 2
fi
app_path="$PWD/dist/Tessera.app"
bash scripts/verify-app-bundle.sh "$app_path"
tools="$(bash scripts/sparkle-tools.sh)"
account="io.github.jgoneit.tessera"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app_path/Contents/Info.plist")"
[[ "$("$tools/generate_keys" --account "$account" -p)" == "$public_key" ]] || {
    printf 'The existing signing key does not match this app.\n' >&2; exit 1;
}
release="$(/usr/libexec/PlistBuddy -c 'Print :TesseraReleaseVersion' "$app_path/Contents/Info.plist")"
architecture="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/Tessera")"
archive_name="Tessera-$release-${architecture// /+}.dmg"
swift scripts/verify-update.swift "$app_path/Contents/Info.plist" website/appcast.xml "dist/$archive_name"
work_dir="$(mktemp -d "$PWD/dist/.tessera-update-test.XXXXXX")"
mkdir -p "$work_dir/server"
/usr/bin/ditto "$app_path" "$work_dir/Tessera.app"
cp "dist/$archive_name" "$work_dir/server/$archive_name"
cp website/appcast.xml "$work_dir/server/appcast.xml"
python3 - "$work_dir" "$port" <<'PY'
import plistlib
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
root = Path(sys.argv[1])
base_url = f'http://localhost:{sys.argv[2]}/'
info_path = root / 'Tessera.app/Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
build = int(info['CFBundleVersion'])
assert build > 1
info['CFBundleVersion'] = str(build - 1)
info['TesseraReleaseVersion'] = f"{info['CFBundleShortVersionString']}-alpha.{build - 1}"
info['SUFeedURL'] = base_url + 'appcast.xml'
info['SUDefaultsDomain'] = 'io.github.jgoneit.tessera.updater-e2e.' + root.name
info['SUEnableAutomaticChecks'] = False
info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
info_path.write_bytes(plistlib.dumps(info))
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
feed_path = root / 'server/appcast.xml'
tree = ET.parse(feed_path)
channel = tree.getroot().find('channel')
for item in list(channel.findall('item')):
    if item.findtext(f'{{{namespace}}}version') != str(build):
        channel.remove(item)
        continue
    enclosure = item.find('enclosure')
    enclosure.set('url', base_url + enclosure.get('url').rsplit('/', 1)[1])
tree.write(feed_path, encoding='utf-8', xml_declaration=True)
PY
/usr/bin/codesign --force --sign - --identifier io.github.jgoneit.tessera "$work_dir/Tessera.app"
/usr/bin/codesign --verify --deep --strict "$work_dir/Tessera.app"
"$tools/sign_update" --account "$account" "$work_dir/server/appcast.xml"
"$tools/sign_update" --account "$account" --verify "$work_dir/server/appcast.xml"
printf '\nPrepared a LOCAL TEST source with the unchanged production DMG as target.\n'
printf 'Fixture: %s/Tessera.app\n' "$work_dir"
printf 'Serve only on loopback: python3 -m http.server %q --bind localhost --directory %q\n' "$port" "$work_dir/server"
printf 'Quit the installed app before launching the fixture. Nothing was installed, launched, or published.\n'
