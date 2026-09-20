# Tessera 알파 릴리스 운영

한국어 | [English](RELEASING.en.md)

이 문서는 빌드·서명·공개 절차를 설명합니다. 각 명령의 실행 성공이나 실제 업데이트 설치를
증명하는 검증 기록은 아닙니다. macOS와 Swift 6, GitHub 저장소·릴리스·Pages에 대한 권한,
Tessera 업데이트 키가 저장된 로그인 키체인이 필요합니다.

## 버전과 서명 키

- `Resources/Info.plist`의 `TesseraReleaseVersion`은 `0.1.0-alpha.4` 같은 표시 버전입니다.
  Git 태그는 앞에 `v`를 붙이고, DMG 파일명에도 전체 표시 버전을 사용합니다.
- `CFBundleShortVersionString`은 `0.1.0` 같은 기본 버전, `CFBundleVersion`은 계속 증가하는
  정수 빌드 번호입니다. 업데이트 순서는 빌드 번호로 판단하므로 새 릴리스에 이전 번호를 재사용하지 않습니다.
- Sparkle은 `Package.swift`와 `Package.resolved`에 **2.10.0**으로 고정합니다.
  `scripts/sparkle-tools.sh`는 고정한 아티팩트의 도구만 찾고 버전·체크섬을 확인합니다.
  별도 경로에서 최신 서명 도구를 내려받아 섞어 쓰지 않습니다.
- 앱과 중첩 구성요소의 ad hoc 코드 서명, DMG의 Ed25519 서명, appcast의 Ed25519 서명은
  각각 필요합니다. 업데이트 서명은 Apple Developer ID 서명이나 공증을 대신하지 않습니다.

### 최초 설정에만 키 생성

**이미 배포한 Tessera의 키가 있다면 이 단계는 건너뜁니다.** 최초 설정은 앱 전용 계정
`io.github.jgoneit.tessera`에 한 번만 수행합니다.

```sh
swift package resolve
TESSERA_SPARKLE_TOOLS="$(bash scripts/sparkle-tools.sh)"
"$TESSERA_SPARKLE_TOOLS/generate_keys" --account io.github.jgoneit.tessera
```

macOS 키체인이 인증을 요청하면 로컬 시스템 창에서 처리합니다. 출력된 **공개키**만
`Resources/Info.plist`의 `SUPublicEDKey`에 넣습니다. 개인키는 로그인 키체인에 보관하며
저장소·릴리스 자산·문서·로그로 내보내지 않습니다.

이후 릴리스에서는 다음 명령으로 기존 공개키만 조회합니다. `-p`는 키를 생성하지 않습니다.

```sh
TESSERA_SPARKLE_TOOLS="$(bash scripts/sparkle-tools.sh)"
"$TESSERA_SPARKLE_TOOLS/generate_keys" --account io.github.jgoneit.tessera -p
```

`prepare-update.sh`도 기존 공개키와 번들 공개키가 같은지 검사합니다. 키가 없거나 다르면
중단합니다. 새 키를 만들어 오류를 우회하면 이미 설치된 앱의 업데이트 신뢰가 끊어집니다.

## 후보 만들기

저장소 루트에서 실행합니다. 먼저 버전·빌드 번호를 정하고 한국어·영어 변경 안내를 하나의
Markdown 파일에 준비합니다. 아래 `TESSERA_RELEASE_NOTES`는 그 파일의 실제 절대 경로로 바꿉니다.

```sh
swift test
bash scripts/build-app.sh
bash scripts/build-dmg.sh --skip-build
TESSERA_RELEASE_NOTES=/absolute/path/to/bilingual-release-notes.md
bash scripts/prepare-update.sh "$TESSERA_RELEASE_NOTES"
```

- `build-app.sh`는 `dist/Tessera.app`에 실행 파일·리소스와 Sparkle 프레임워크·도우미를 묶습니다.
  내부 구성요소부터 ad hoc 서명하고, 아키텍처·링크·로딩 경로·설정을 검사합니다.
- `build-dmg.sh --skip-build`는 검증한 번들을 다시 빌드하지 않고 포장합니다.
  alpha.4 arm64의 결과는 `dist/Tessera-0.1.0-alpha.4-arm64.dmg`입니다.
- `prepare-update.sh <안내.md>`는 기존 키로 DMG와 업데이트 목록을 서명합니다.
  한영 안내를 목록에 포함하고, `website/appcast.xml`과 `dist/SHA256SUMS`를 생성합니다.
  현재 도구는 알파 채널의 전체 DMG를 배포하며 델타 업데이트를 만들지 않습니다.
- 스크립트는 Git 커밋·릴리스·Pages 공개나 설치 앱 교체를 수행하지 않습니다.
  최종 후보를 만든 뒤 소스·번들·DMG를 바꾸면 다시 빌드·검증·서명해야 합니다.

키체인 없이 공개키만으로 목록과 DMG를 검증할 수 있습니다.

```sh
swift scripts/verify-update.swift \
  dist/Tessera.app/Contents/Info.plist website/appcast.xml \
  dist/Tessera-0.1.0-alpha.4-arm64.dmg
(cd dist && shasum -a 256 -c SHA256SUMS)
node --test website/*.test.mjs
node --check website/app.mjs
```

`verify-update.swift`는 목록 서명·DMG 서명·길이·빌드와 태그별 다운로드 주소를 확인합니다.
DMG를 생략하면 목록만 검증합니다. `bash scripts/test-update-verification.sh`는 임시 시험 키로
검증기의 정상·변조 사례를 검사하며 배포 키가 필요하지 않습니다. 별도로 DMG를 읽기 전용으로
마운트해 앱·Applications 링크·한영 설치 안내를 확인하고, 확인 뒤 마운트를 해제합니다.

## 실제 업데이트 시험

공개할 최종 DMG는 그대로 두고, 설치 출발점으로만 이전 빌드 번호의 로컬 시험 앱을 만듭니다.
서명된 최종 appcast와 DMG를 먼저 준비한 뒤 실행합니다.

```sh
bash scripts/prepare-update-test.sh 8769
```

스크립트가 생성한 `dist/.tessera-update-test.<임의값>/Tessera.app` 경로와 서버 명령을 출력합니다.
시험 앱은 빌드 번호만 낮추고 loopback 피드를 사용하며, Sparkle 설정에 고유한 `SUDefaultsDomain`을
지정하고 자동 확인을 끕니다. 시험 피드는 같은 키로 다시 서명하지만, 대상 DMG 바이트는 바꾸지 않습니다.
이 앱·피드·localhost URL은 공개하거나 실제 설치본으로 배포하지 않습니다.

1. 현재 설치 앱과 사용자 설정을 백업하고, 실행 중인 Tessera를 종료합니다. 시험 앱과 설치 앱을 동시에 실행하지 않습니다.
2. 출력된 `python3 -m http.server ... --bind localhost --directory ...` 명령으로 로컬 서버를 시작하고 시험 앱을 엽니다.
3. 수동 업데이트 확인에서 취소·잘못된 피드·변조된 DMG의 거부를 검사합니다. 기존 앱이 교체되지 않았는지 확인합니다.
   실패 사례를 만들 때는 시험 디렉터리 안의 사본만 수정합니다.
4. 정상 시험 피드와 최종 DMG로 다운로드·설치·재실행을 진행합니다. 재실행한 앱의 버전과 실행 파일 해시를
   최종 번들과 비교합니다. 단축키 등록·창 이동·설정 보존·손쉬운 사용 권한은 별도로 확인합니다.
5. 시험 프로세스와 서버를 종료하고 임시 시험 앱·피드·시험 전용 Sparkle 설정을 정리합니다.
   일반 Tessera 설정을 삭제하지 않습니다. 최종 앱이 다시 실행된 경로를 확인한 뒤 설치본 사용을 재개합니다.

`SUDefaultsDomain`은 **Sparkle 설정만** 격리합니다. Tessera의 격자·테마·단축키 설정은 같은 번들
식별자를 사용하므로 백업과 전후 비교가 필요합니다. 최종 앱에는 시험용 피드·도메인·ATS 예외가 없어야 합니다.
코드 서명 검사는 실제 설치 성공, 접근성 승인, 다른 Mac의 Gatekeeper 허용을 대신하지 않습니다.

## 공개 순서와 복구

1. 한영 README·설치 안내·웹페이지의 버전과 링크를 최종 파일명에 맞춥니다. 새 소스 변경·문서·서명된
   appcast를 목적별로 커밋하고 PR 검사 및 해당 Seal Task의 `verify`·반환된 Run ID의 `complete`를 수행합니다.
2. **검증한 정확한 소스 커밋**으로 `v0.1.0-alpha.4` 같은 사전 릴리스를 만듭니다.
   최종 DMG와 `SHA256SUMS`를 첨부하고 기존 릴리스·자산은 보존합니다.
3. 공개 URL에서 두 파일을 다시 내려받아 체크섬과 서명을 확인합니다. 아직 없는 자산을 가리키는 목록을 먼저 배포하지 않습니다.
4. PR을 병합해 Pages를 배포하고 `https://jgoneit.github.io/tessera/appcast.xml`의 서명을 확인합니다.
   공개 한영 다운로드 링크와 설치본의 수동 업데이트 확인도 점검합니다.
5. 실제 결과와 미검증 항목을 한영 검증 기록에 남깁니다. **alpha.3 이하에는 업데이터가 없으므로
   업데이트를 받으려면 alpha.4를 한 번 직접 설치해야 한다**는 안내를 유지합니다.

최종 appcast는 서명 후 직접 수정해 배포하지 않습니다. 필요한 변경을 스테이징한 뒤 기존 키로 다시
서명하고 공개키 검증을 통과한 파일만 배포합니다. 잘못된 업데이트는 해당 항목을 목록에서 철회한 뒤
다시 서명합니다. 이미 설치된 앱의 수정은 **더 높은 빌드 번호**로 배포하며 자동 다운그레이드는 제공하지 않습니다.
공개된 DMG를 같은 이름으로 몰래 교체하지 않습니다. 설치 앱의 수동 복구에는 보관한 이전 앱을 사용하고,
ad hoc 서명 변경으로 접근성 재승인이 필요할 수 있음을 확인합니다.
