#!/bin/bash
set -euo pipefail
if [[ "$#" != 1 || ! -d "$1/Contents/Frameworks/Sparkle.framework" ]]; then
    printf 'Usage: bash scripts/sign-app.sh <Tessera.app>\n' >&2
    exit 2
fi
app_path="$1"
framework="$app_path/Contents/Frameworks/Sparkle.framework"
# Nested helpers retain their framework-provided entitlements. Do not use
# --deep when signing: each executable has its own signing requirements.
for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    /usr/bin/codesign --force --sign - --options runtime --preserve-metadata=entitlements \
        "$framework/Versions/B/$component"
done
/usr/bin/codesign --force --sign - --options runtime "$framework"
/usr/bin/codesign --force --sign - --identifier io.github.jgoneit.tessera "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
