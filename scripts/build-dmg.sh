#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    printf 'Usage: bash scripts/build-dmg.sh [--skip-build]\n'
    printf 'Build Tessera.app and package a local DMG; --skip-build packages the existing dist/Tessera.app.\n'
}

skip_build=false
for argument in "$@"; do
    case "$argument" in
        --skip-build) skip_build=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$skip_build" == false ]]; then
    bash scripts/build-app.sh
fi

app_path="$PWD/dist/Tessera.app"
info_path="$app_path/Contents/Info.plist"
if [[ ! -d "$app_path" || ! -f "$info_path" ]]; then
    printf 'Missing dist/Tessera.app. Run bash scripts/build-app.sh first.\n' >&2
    exit 1
fi

/usr/bin/plutil -lint "$info_path"
/usr/bin/codesign --verify --strict "$app_path"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_path")"
executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_path")"
if [[ ! "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    printf 'CFBundleShortVersionString cannot be used in a DMG filename.\n' >&2
    exit 1
fi
if [[ ! "$executable_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    printf 'CFBundleExecutable must be an executable filename.\n' >&2
    exit 1
fi

app_executable="$app_path/Contents/MacOS/$executable_name"
if [[ ! -f "$app_executable" || ! -x "$app_executable" ]]; then
    printf 'The app bundle executable is missing or not executable.\n' >&2
    exit 1
fi
architectures="$(/usr/bin/lipo -archs "$app_executable")"
architecture_label="${architectures// /+}"
if [[ ! "$architecture_label" =~ ^[A-Za-z0-9_+-]+$ ]]; then
    printf 'Could not determine the app executable architecture.\n' >&2
    exit 1
fi

output_path="$PWD/dist/Tessera-$version-$architecture_label.dmg"
if [[ -e "$output_path" && ! -f "$output_path" ]]; then
    printf 'The DMG output path exists and is not a regular file.\n' >&2
    exit 1
fi

# Keep staging and the temporary image beside the final output. An unsuccessful
# create/verify leaves an existing DMG intact; only a verified image replaces it.
work_dir="$(mktemp -d "$PWD/dist/.tessera-dmg.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

staging_path="$work_dir/contents"
temporary_image="$work_dir/Tessera.dmg"
mkdir -p "$staging_path"
/usr/bin/ditto "$app_path" "$staging_path/Tessera.app"
/bin/ln -s /Applications "$staging_path/Applications"
cat > "$staging_path/INSTALL.txt" <<'INSTALL_TEXT'
Tessera — 로컬 설치 / Local installation

한국어
1. 실행 중인 Tessera가 있으면 메뉴바에서 종료하세요.
2. Tessera.app을 옆의 Applications 폴더로 드래그하세요.
   기존 앱을 교체한다면 필요한 이전 버전은 먼저 따로 보관하세요.
3. 이 디스크를 추출하고 응용 프로그램 폴더의 Tessera를 실행하세요.
4. Dock 아이콘은 없습니다. 메뉴바의 세 칸 아이콘에서 설정을 여세요.
5. 시스템 설정 > 개인정보 보호 및 보안 > 손쉬운 사용에서 설치한 Tessera를 허용하세요.
   설정의 새로고침 버튼으로 권한을 확인하세요.

이 앱은 로컬 ad hoc 서명이며 Developer ID 서명·Apple 공증을 포함하지 않습니다.
DMG는 설치 파일 묶음이며 공증이나 macOS 보안 검사를 대신하지 않습니다.

English
1. Quit any running Tessera from its menu bar menu.
2. Drag Tessera.app to Applications. Keep a separate copy of an older app before replacing it.
3. Eject this disk, then open Tessera from Applications.
4. Tessera has no Dock icon. Use its three-tile menu bar icon to open Settings.
5. Allow the installed Tessera in System Settings > Privacy & Security > Accessibility.
   Use the refresh button in Tessera Settings to check access.

This local app is ad hoc signed, without Developer ID signing or Apple notarization.
A DMG packages the app; it does not replace notarization or macOS security checks.
INSTALL_TEXT

/usr/bin/codesign --verify --strict "$staging_path/Tessera.app"
/usr/bin/hdiutil create -srcfolder "$staging_path" -volname "Tessera" \
    -fs HFS+ -format UDZO "$temporary_image"
/usr/bin/hdiutil verify "$temporary_image"
/bin/mv -f "$temporary_image" "$output_path"
printf 'Created and checksum-verified local DMG: %s\n' "$output_path"
