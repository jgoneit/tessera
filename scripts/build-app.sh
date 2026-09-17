#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Tessera
bin_dir="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/Tessera.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
install -m 755 "$bin_dir/Tessera" "$app_path/Contents/MacOS/Tessera"
install -m 644 Resources/Info.plist "$app_path/Contents/Info.plist"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier io.github.jgoneit.tessera "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf 'Built and verified: %s\n' "$app_path"
