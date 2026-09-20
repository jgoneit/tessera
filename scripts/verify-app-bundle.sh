#!/bin/bash
set -euo pipefail
if [[ "$#" != 1 ]]; then
    printf 'Usage: bash scripts/verify-app-bundle.sh <Tessera.app>\n' >&2
    exit 2
fi
app_path="$1"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$app_path"
python3 - "$app_path" <<'PY'
import base64
import plistlib
import re
import subprocess
import sys
from pathlib import Path
app = Path(sys.argv[1]).resolve()
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'io.github.jgoneit.tessera'
assert info['CFBundleVersion'].isdigit() and int(info['CFBundleVersion']) > 0, 'Build number must increase numerically.'
assert re.fullmatch(re.escape(info['CFBundleShortVersionString']) + r'(?:-alpha\.[1-9][0-9]*)?', info['TesseraReleaseVersion']), 'Invalid release display version.'
assert info['SUFeedURL'] == 'https://jgoneit.github.io/tessera/appcast.xml'
assert len(base64.b64decode(info['SUPublicEDKey'], validate=True)) == 32, 'Missing valid updater public key.'
assert info['SUEnableAutomaticChecks'] is True
assert info['SUScheduledCheckInterval'] == 86400
assert info['SUAutomaticallyUpdate'] is False and info['SUAllowsAutomaticUpdates'] is False
assert info['SUEnableSystemProfiling'] is False
assert info['SUVerifyUpdateBeforeExtraction'] is True and info['SURequireSignedFeed'] is True
framework = app / 'Contents/Frameworks/Sparkle.framework'
license_text = (app / 'Contents/Resources/Sparkle-LICENSE.txt').read_text()
assert 'Andy Matuschak' in license_text and 'EXTERNAL LICENSES' in license_text
assert (framework / 'Versions/Current').is_symlink()
for name in ['Sparkle', 'Resources', 'Autoupdate', 'Updater.app', 'XPCServices']:
    path = framework / name
    assert path.is_symlink() and path.exists(), f'Broken framework link: {name}'
    assert path.resolve().is_relative_to(framework), f'Escaping framework link: {name}'
executable = app / 'Contents/MacOS/Tessera'
architectures = set(subprocess.check_output(['/usr/bin/lipo', '-archs', executable], text=True).split())
for component in ['Sparkle', 'Autoupdate', 'Updater.app/Contents/MacOS/Updater',
                  'XPCServices/Installer.xpc/Contents/MacOS/Installer',
                  'XPCServices/Downloader.xpc/Contents/MacOS/Downloader']:
    supported = set(subprocess.check_output(['/usr/bin/lipo', '-archs', framework / component], text=True).split())
    assert architectures <= supported, f'Unsupported framework architecture: {component}'
linked = subprocess.check_output(['/usr/bin/otool', '-L', executable], text=True)
assert '@rpath/Sparkle.framework/Versions/B/Sparkle' in linked
commands = subprocess.check_output(['/usr/bin/otool', '-l', executable], text=True)
assert 'path @executable_path/../Frameworks ' in commands, 'Missing bundled framework runpath.'
print('Verified updater configuration, embedded helpers, architectures, symlinks and runtime load path.')
PY
