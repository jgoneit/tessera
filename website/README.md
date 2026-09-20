# Tessera 소개페이지

한국어 | [English](README.en.md)

사용자가 제공한 `tessera---macos-grid-window-manager.zip`의 색상, 글자 크기, 카드와
다운로드 동선을 바탕으로 만든 정적 소개페이지다. 원본 ZIP은 수정하지 않았다.
공개 주소는 <https://jgoneit.github.io/tessera/>이다. 로컬 미리보기와 GitHub Pages
배포에 동일한 파일을 사용한다.

저장소 루트에서 실행한 뒤 표시된 주소를 브라우저로 연다:

```sh
python3 -m http.server 8080 --bind 127.0.0.1 --directory website
```

`http://127.0.0.1:8080`에서 확인한다. ES modules를 사용하므로 HTML 파일을 직접 여는
대신 HTTP 미리보기를 사용한다. 패키지 설치와 빌드는 필요 없다.

## 데모

- 2×2, 3×2, 4×2를 함께 선택할 수 있고 마지막 선택은 해제할 수 없다.
- 새 격자를 체크하면 그 격자의 가까운 열을 즉시 미리보기에 표시한다. 기존 격자
  선택과 높이는 유지하며, 이후 좌우 이동은 선택된 모든 격자를 함께 순회한다.
- 선택된 열 중심의 가로 순서로 좌우 이동하며 양 끝에서 순환한다.
- 위칸 ↔ 열 전체 ↔ 아래칸을 한 단계씩 이동하고 위아래 끝에서는 멈춘다.
- 체험 영역이나 격자 체크박스에 포커스가 있을 때 Return으로 최대화한다.
  최대화 버튼도 사용할 수 있으며, 최대화는 Gap 없이 사용 가능 영역을 채운다.
  이후 위/아래는 화면 반쪽 ↔ 최대화 사이를 이동하고, 좌우는 높이를 유지해 격자로 돌아간다.
- 숫자는 위 행부터 1–4, 1–6, 1–8로 표시된다. 열 전체는 두 행을 연결해 강조한다.
- 격자 체크박스 또는 체험 영역에 포커스가 있을 때만 방향키와 숫자를 처리한다.
  격자 선택 후 추가 클릭 없이 방향키를 사용할 수 있다. 체크박스 포커스를 유지하므로
  Tab/Shift+Tab과 Space로 다른 격자를 계속 선택할 수 있다. 상하 키 반복은 무시하고,
  Esc 또는 영역 밖 클릭으로 일반 페이지 탐색을 계속할 수 있다.
- 방향·숫자 버튼을 마우스로 누르거나 해당 버튼에서 방향키·숫자키를 사용하면 체험 영역으로
  포커스를 옮겨 곧바로 Return을 사용할 수 있다. Tab으로 선택한 버튼의 Enter/Space는
  원래 버튼을 실행한다. 체험 영역의 Return 반복은 무시하며, 조합키와 한글 입력 조합 중 키 이벤트는
  가로채지 않는다.
- 웹에서는 숫자·클릭으로 반복 체험할 수 있도록 미리보기를 유지한다. 실제 앱의
  선택기가 숫자·클릭 배치 후 닫히는 동작과는 구별된다.
- 데모는 명시적인 중앙 열에서 시작하며 실제 AX 창 확보·프레임 인식·앱 제약을
  재현하지 않는다. 실제 앱 코드와 별도의 브라우저용 모델이다.

## 언어

상단의 **EN / 한국어** 버튼으로 소개·설치 안내와 데모의 현재 배치·접근성 이름을
함께 전환한다. 격자 선택, 현재 열·높이와 테마는 그대로 유지한다.

- [한국어](https://jgoneit.github.io/tessera/?lang=ko) · [English](https://jgoneit.github.io/tessera/?lang=en)
- 유효한 URL의 `lang` → 저장한 선택 → 브라우저의 첫 지원 언어 순서로 적용한다.
  지원 언어가 없으면 영어를 사용한다. 버튼으로 선택한 언어는 브라우저에 저장한다.
- 번역은 `i18n.mjs`에서 관리한다. 한국어 정적 HTML이 기본이며 JavaScript 실행 후
  문서 언어·제목·설명도 갱신한다. JavaScript를 실행하지 않는 링크 미리보기는
  영어 URL에서도 한국어 제목을 표시할 수 있다.
- JavaScript가 꺼져 있어도 다운로드와 한·영 문서 안내는 제공한다.

## 검증

2026-09-20 Return 최대화 변경에서 웹 테스트 49개와 JavaScript 구문 검사가 통과했다.
로컬 브라우저에서 격자 선택·방향 이동 후 Return, 숫자패드 Enter, 최대화 후 상하·좌우 이동,
마우스 배치 후 Return, Tab으로 고른 버튼의 Enter/Space, Control+Option+Return 미가로채기,
Esc 후 Return 무반응을 확인했다. 한영 안내와 영문 라이트 테마의 320px 화면에서 가로 넘침이
없는 것도 확인했다. 물리 키 반복·한글 IME와 다른 브라우저 엔진은 이번에 별도 검증하지 않았다.

```sh
node --test website/*.test.mjs
```

기존 앱의 Seal 검사와 웹 검증 범위는 [소개페이지 검증 기록](../docs/landing-page-validation.md)에,
이번 번역·언어 전환 검증은 [영문 지원 검증 기록](../docs/bilingual-validation.md)에 별도로 기록한다.
다운로드 링크의 대상 버전은 `v0.1.0-alpha.3`이다. 새 릴리스로 바꿀 때는
두 다운로드 링크와 설치 안내 링크를 함께 갱신한다.
`app.mjs` 변경 시 `index.html`의 script URL에 있는 `v`도 파일의 SHA-256 앞 12자리로
갱신한다. 기존 방문자가 캐시된 이전 스크립트를 계속 실행하는 것을 막기 위한 값이다.
`navigation.mjs` 또는 `i18n.mjs`를 변경하면 해당 import URL의 버전을 갱신한 뒤
app 버전을 갱신한다. `styles.css`도 HTML의 stylesheet URL에 같은 방식으로 버전을
넣는다. `assets.test.mjs`는 각 버전이 실제 파일 내용과 일치하는지 확인한다.

## GitHub Pages

`.github/workflows/pages.yml`은 `main`의 페이지/워크플로 변경 시 Node 테스트와
구문 검사를 통과한 파일만 GitHub Pages로 배포한다. PR에서는 준비/검사만 수행한다.
Actions 화면에서 수동 실행할 수도 있다.

공개 파일은 `index.html`, `styles.css`, `app.mjs`, `navigation.mjs`, `i18n.mjs`, `mark.svg`와
워크플로가 생성하는 `.nojekyll`이다. 테스트·문서·네이티브 앱 파일은 웹 경로에
배포하지 않는다. 저장소 Pages 설정의 Source는 **GitHub Actions**를 사용한다.

파일 참조는 상대 경로이므로 `/tessera/` 경로와 독립 도메인의 루트 모두 지원한다.
별도 도메인을 연결할 때는 GitHub Pages의 **Custom domain** 설정과 해당 도메인의
DNS를 함께 설정한다. Actions 배포에는 CNAME 파일을 추가할 필요가 없다.
공식 안내: <https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site>
