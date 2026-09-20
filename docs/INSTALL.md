# Tessera 로컬 설치

[한국어](INSTALL.md) | [English](INSTALL.en.md)

Apple Developer Program에 가입하지 않아도 직접 빌드한 Tessera를 본인 Mac의 응용 프로그램 폴더에
설치해 사용할 수 있습니다. 현재 빌드는 로컬 **ad hoc 서명**이며 Developer ID 서명과 Apple 공증은
포함하지 않습니다. DMG는 앱을 복사하기 편하게 묶은 디스크 이미지이고, 공증을 대신하지 않습니다.
개발·개인 기기 테스트와 Developer ID·공증의 제공 범위는 [Apple의 멤버십 안내](https://developer.apple.com/support/compare-memberships/)에서 확인할 수 있습니다.

macOS 14 이상이 필요합니다. 기본 빌드는 **빌드한 Mac의 아키텍처만** 대상으로 하며 Universal 앱이나
교차 컴파일을 만들지 않습니다. 예를 들어 Apple Silicon에서 빌드한 `arm64` 앱의 실행을 Intel Mac까지
검증한 것은 아닙니다.

현재 릴리스는 **0.1.0-alpha.4**이며, Apple Silicon용 설치 파일은
[`Tessera-0.1.0-alpha.4-arm64.dmg`](https://github.com/jgoneit/tessera/releases/download/v0.1.0-alpha.4/Tessera-0.1.0-alpha.4-arm64.dmg)입니다.
**alpha.3 이하를 사용 중이라면 이 DMG를 한 번 직접 설치해야 앱 안의 업데이트 기능을 사용할 수 있습니다.**

## 앱을 직접 설치하기

1. 소스에서 빌드하려면 Swift 6 이상과 macOS SDK를 준비하고 저장소 루트에서 실행합니다.

   ```sh
   bash scripts/build-app.sh
   ```

2. 실행 중인 Tessera가 있다면 메뉴바의 Tessera 아이콘에서 **종료 / Quit Tessera**를 선택합니다.
3. Finder에서 `dist/Tessera.app`을 **응용 프로그램**(`/Applications`)으로 복사합니다.
   기존 버전을 교체한다면 먼저 별도 위치에 보관합니다. Finder에서 쓰기 권한을 요청할 수 있습니다.
   개인용 응용 프로그램 폴더를 쓰는 경우 `~/Applications`에 복사해도 됩니다.
4. 복사한 위치의 `Tessera.app`을 실행합니다. 이후에는 설치한 앱을 사용합니다.

Tessera는 **메뉴바 앱**입니다. 메뉴바 오른쪽의 세 칸 아이콘을 누르면 설정·창 배치·종료 메뉴를
사용할 수 있습니다. 설정 창이나 업데이트 창을 열면 창은 Mission Control에, 앱 아이콘은 Dock·⌘Tab에 표시됩니다.
설정을 최소화하거나 다른 앱 뒤로 보내도 앱 아이콘은 유지됩니다. 설정 창과 업데이트 창을 모두 닫으면 메뉴바 전용으로
돌아가며 Tessera는 계속 실행됩니다. 선택기나 배치 안내만 표시할 때는 Dock 아이콘이 생기지 않습니다.

## DMG로 설치하기

1. `Tessera-<버전>-<아키텍처>.dmg`를 더블 클릭합니다.
2. 이미지 안의 `Tessera.app`을 옆의 **Applications** 폴더로 드래그합니다.
   실행 중인 Tessera는 먼저 종료하고, 필요한 이전 버전은 교체 전에 보관합니다.
3. 복사가 끝나면 Finder에서 Tessera 디스크를 추출합니다.
4. 응용 프로그램 폴더에 복사한 Tessera를 실행합니다. 디스크 이미지 안의 앱을 계속 실행하지 않습니다.

DMG에는 `Tessera.app`, `/Applications`를 가리키는 링크, 한국어·영어 `INSTALL.txt`가 들어 있습니다.
자동 설치나 권한 변경은 수행하지 않습니다.

## 업데이트하기

alpha.4부터 메뉴와 설정의 **업데이트 확인 / Check for Updates…**로 새 버전을 확인합니다.
앱 설정에는 `0.1.0-alpha.4`처럼 설치한 전체 릴리스 버전이 표시됩니다.

1. 메뉴나 설정에서 **업데이트 확인**을 누릅니다. 확인 중·최신 버전·확인 실패를 구분해 표시합니다.
2. 새 버전이 있으면 버전과 변경 내용을 읽고 **설치**를 선택합니다.
3. Tessera가 업데이트를 내려받아 서명을 검증하고 앱을 교체한 뒤 다시 실행합니다. 격자·간격·언어·테마·단축키는 유지됩니다.
4. 창 이동 권한이 다시 필요하면 아래 손쉬운 사용 권한 절차를 확인합니다.

자동 확인은 **기본 켜짐, 하루 한 번**이며 설정에서 끌 수 있습니다. 꺼도 수동 확인은 가능합니다.
자동 확인은 **새 버전 있음**을 메뉴와 설정에 표시하며 작업 중 창을 열거나 포커스를 가져오지 않습니다.
사용자가 설치를 선택하기 전에는 자동 다운로드나 무인 설치를 하지 않습니다. 확인 실패 시 기존 앱과 창 배치 기능을 계속 사용할 수 있습니다.
알파 앱은 알파·정식 업데이트를 확인하며, 정식 앱은 정식 업데이트만 확인합니다.
Tessera의 상태 문구는 앱에서 선택한 한국어·영어를 따르고, Sparkle 기본 설치 창은 macOS의 선호 언어를 사용합니다.

alpha.3 이하에는 이 기능이 없으므로 새 DMG를 직접 설치하세요. 필요하면 이후에도 DMG로 수동 교체할 수 있습니다.
같은 Mac에서 개발용 앱과 설치 앱을 동시에 실행하지 마세요.

## 창 이동 권한 확인

1. Tessera 설정에서 **설정 열기 / Open Settings**를 누릅니다.
2. **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용**에서 **설치한 위치의 Tessera**를 허용합니다.
   목록에 없으면 `+`를 눌러 `/Applications/Tessera.app` 또는 실제로 복사한 앱을 선택합니다.
3. Tessera 설정의 새로고침 버튼(**다시 확인 / Check Again**)을 눌러 준비 상태를 확인합니다.
4. 다른 앱의 일반 창을 활성화한 뒤 기존 방향 단축키로 배치합니다.

개발 폴더에서 실행하던 앱을 응용 프로그램 폴더로 옮기거나 ad hoc 앱을 재빌드·업데이트하면 접근성 승인을
다시 확인해야 할 수 있습니다. 시스템 설정에는 켜짐으로 보여도 Tessera가 권한을 요구한다면 기존 Tessera
항목만 제거하고 **현재 설치한 앱**을 다시 추가한 뒤 Tessera를 재실행해 확인합니다. 다른 앱의 승인에는 손대지 않습니다.
격자·간격·언어·테마·단축키는 같은 사용자 계정의 기존 설정을 사용합니다.

## 최대화와 화면 반쪽 배치

기본 **⌃⌥Return**으로 현재 창을 메뉴바·Dock을 제외한 사용 가능 영역에 여백 없이 최대화합니다.
메뉴와 선택기의 **최대화 / Maximize** 버튼으로도 사용할 수 있습니다. 다시 실행해도 최대화를 유지하며,
macOS의 별도 Spaces 전체화면으로 전환하지 않습니다.

최대화 상태에서 **⌃⌥↑ / ⌃⌥↓**는 화면 위쪽·아래쪽 절반으로 이동합니다. 위쪽 절반에서 아래,
아래쪽 절반에서 위를 누르면 최대화로 돌아갑니다. **⌃⌥← / ⌃⌥→**는 높이를 유지한 채 선택한
격자의 열로 진입합니다. 화면 반쪽에는 설정한 간격이 적용됩니다. 최대화 단축키를 등록할 수 없으면
기존 방향키는 유지되고 설정에 안내가 표시되며, 메뉴·버튼으로 최대화할 수 있습니다.

## 로컬 DMG 만들기

저장소 루트에서 다음 명령을 실행합니다. 기본 동작은 release 앱을 먼저 빌드한 뒤 포장합니다.

```sh
bash scripts/build-dmg.sh
```

이미 검증한 `dist/Tessera.app`을 다시 빌드하거나 재서명하지 않고 포장하려면 다음을 사용합니다.

```sh
bash scripts/build-dmg.sh --skip-build
```

파일명은 앱 번들의 전체 릴리스 버전과 실행 파일의 실제 아키텍처에서 정합니다.
예를 들어 릴리스가 0.1.0-alpha.4이고 arm64 실행 파일이면 `dist/Tessera-0.1.0-alpha.4-arm64.dmg`가 생성됩니다.
스크립트는 앱의 코드 서명을 확인하고, 임시 폴더에 복사한 번들에도 같은 검사를 수행합니다.
`hdiutil create`로 UDZO 압축 이미지를 만들고 `hdiutil verify`로 이미지 체크섬을 검사한 뒤 최종 경로에 놓습니다.
같은 이름의 DMG가 있으면 새 이미지 검증이 성공한 뒤 교체합니다. 실패나 중단 시 임시 파일은 정리합니다.

이 검사는 앱의 실제 창 이동, 접근성 승인, Gatekeeper 허용 또는 공증 성공을 뜻하지 않습니다.
이미지 마운트·설치·앱 실행은 별도 단계이며 스크립트가 자동으로 수행하지 않습니다.

업데이트 배포에는 앱의 코드 서명과 별도로 Sparkle Ed25519 서명이 필요합니다. 같은 DMG를 GitHub Releases의
일반 다운로드와 앱 업데이트에 사용하고, GitHub Pages의 `https://jgoneit.github.io/tessera/appcast.xml`에
서명된 업데이트 목록을 배포합니다. 업데이트 개인키는 로컬 로그인 키체인에 보관하며 저장소나 릴리스에 넣지 않습니다.
로컬 DMG 생성만으로 업데이트 목록을 공개하거나 기존 사용자에게 업데이트를 제공하지는 않습니다.

## 서명과 배포 범위

`codesign --sign -`의 ad hoc 서명은 Developer ID 인증서가 있는 배포 서명과 다릅니다.
다른 Mac으로 전송하거나 인터넷에서 내려받은 경우 Gatekeeper 경고가 표시될 수 있습니다.
현재 DMG로 모든 Mac에서 경고 없이 실행된다고 보장하지 않습니다. macOS가 실행을 막으면 앱의 출처와
시스템 안내를 확인하며, 이 설치 절차는 보안 검사 설정을 변경하지 않습니다.
일반 사용자 배포를 준비할 때 필요한 Developer ID 서명·공증은 [Apple의 배포 서명 안내](https://developer.apple.com/developer-id/)를 참고하세요.

## English quick guide

- Requires macOS 14 or later. The default build targets the current Mac's architecture only.
- Quit the running Tessera, keep any older app you need, and copy `Tessera.app` to Applications.
  For a DMG, drag the app onto its Applications link, eject the disk, and open the installed copy.
- Tessera lives in the menu bar. Opening Settings or an update window shows its window in Mission Control and its icon in the Dock and ⌘Tab.
  The app icon remains while Settings is minimized or behind another app; closing both windows returns to menu bar-only mode.
- From alpha.4, use **Check for Updates…** in the menu or Settings. Automatic checks run quietly once a day by default; installation requires your action.
  alpha.3 and earlier need one manual DMG installation first. Updating may require renewing Accessibility permission.
- Allow the installed app in **System Settings → Privacy & Security → Accessibility**, then use **Check Again** in Tessera Settings.
- Use **⌃⌥Return** to maximize, then **⌃⌥↑ / ⌃⌥↓** for screen halves or **⌃⌥← / ⌃⌥→** to enter a selected grid.
- Run `bash scripts/build-dmg.sh` to build and package, or add `--skip-build` to package an existing verified bundle.
  Output is `dist/Tessera-<version>-<architecture>.dmg`.
- This is a local ad hoc build without Developer ID signing or Apple notarization. A DMG does not replace
  notarization or grant permission to run. Installation and packaging do not change macOS security settings.
