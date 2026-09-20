#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Tessera
bin_dir="$(swift build -c release --show-bin-path)"
mkdir -p "$PWD/dist"
work_dir="$(mktemp -d "$PWD/dist/.tessera-app.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
app_path="$work_dir/Tessera.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
install -m 755 "$bin_dir/Tessera" "$app_path/Contents/MacOS/Tessera"
install -m 644 Resources/Info.plist "$app_path/Contents/Info.plist"
bash scripts/sparkle-tools.sh >/dev/null
framework="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$framework" ]] || { printf 'Missing pinned Sparkle framework.\n' >&2; exit 1; }
/usr/bin/ditto "$framework" "$app_path/Contents/Frameworks/Sparkle.framework"
install -m 644 .build/artifacts/sparkle/Sparkle/LICENSE "$app_path/Contents/Resources/Sparkle-LICENSE.txt"
/usr/bin/ditto "$bin_dir/Tessera_TesseraApp.bundle" "$app_path/Contents/Resources/Tessera_TesseraApp.bundle"
for language in en ko; do
    /usr/bin/plutil -lint "$app_path/Contents/Resources/Tessera_TesseraApp.bundle/Contents/Resources/$language.lproj/Localizable.strings"
done
scripts/build-icon.sh
install -m 644 .build/icons/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$app_path/Contents/Info.plist"
touch "$app_path"
bash scripts/sign-app.sh "$app_path"
bash scripts/verify-app-bundle.sh "$app_path"
bash scripts/test-update-verification.sh
if [[ -f website/appcast.xml ]]; then
    swift scripts/verify-update.swift "$app_path/Contents/Info.plist" website/appcast.xml
fi
# Only a fully verified replacement can replace the previous local bundle.
if [[ -e "$PWD/dist/Tessera.app" ]]; then
    mv "$PWD/dist/Tessera.app" "$work_dir/previous.app"
fi
mv "$app_path" "$PWD/dist/Tessera.app"
printf 'Built and verified: %s\n' "$PWD/dist/Tessera.app"
