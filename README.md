# Tessera

macOS용 Grid-first Window Manager. 화면의 Zone을 선택해 현재 창을 배치합니다.

## 개발

macOS 14 이상과 Swift 6 도구 체인이 필요합니다. 외부 패키지는 사용하지 않습니다.

```sh
swift test
bash scripts/build-app.sh
```

번들은 `dist/Tessera.app`에 생성되며 로컬 ad hoc 서명을 사용합니다.
현재 커밋은 제품 기능 구현 전 프로젝트 기반 구성입니다.
