# Tessera 소개페이지

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
- 숫자는 위 행부터 1–4, 1–6, 1–8로 표시된다. 열 전체는 두 행을 연결해 강조한다.
- 체험 영역에 포커스가 있을 때만 방향키와 숫자를 처리한다. 상하 키 반복은 무시하고,
  Esc 또는 영역 밖 클릭으로 일반 페이지 탐색을 계속할 수 있다.
- 웹에서는 숫자·클릭으로 반복 체험할 수 있도록 미리보기를 유지한다. 실제 앱의
  선택기가 숫자·클릭 배치 후 닫히는 동작과는 구별된다.
- 데모는 명시적인 중앙 열에서 시작하며 실제 AX 창 확보·프레임 인식·앱 제약을
  재현하지 않는다. 실제 앱 코드와 별도의 브라우저용 모델이다.

## 검증

```sh
node --test website/navigation.test.mjs
```

기존 앱의 Seal 검사와 웹 검증 범위는 `../docs/landing-page-validation.md`에 별도로 기록한다.
다운로드 링크는 검증된 `v0.1.0-alpha.1` 릴리스를 가리킨다. 새 릴리스로 바꿀 때는
두 다운로드 링크와 설치 안내 링크를 함께 갱신한다.

## GitHub Pages

`.github/workflows/pages.yml`은 `main`의 페이지/워크플로 변경 시 Node 테스트와
구문 검사를 통과한 파일만 GitHub Pages로 배포한다. PR에서는 준비/검사만 수행한다.
Actions 화면에서 수동 실행할 수도 있다.

공개 파일은 `index.html`, `styles.css`, `app.mjs`, `navigation.mjs`, `mark.svg`와
워크플로가 생성하는 `.nojekyll`이다. 테스트·문서·네이티브 앱 파일은 웹 경로에
배포하지 않는다. 저장소 Pages 설정의 Source는 **GitHub Actions**를 사용한다.

파일 참조는 상대 경로이므로 `/tessera/` 경로와 독립 도메인의 루트 모두 지원한다.
별도 도메인을 연결할 때는 GitHub Pages의 **Custom domain** 설정과 해당 도메인의
DNS를 함께 설정한다. Actions 배포에는 CNAME 파일을 추가할 필요가 없다.
공식 안내: <https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site>
